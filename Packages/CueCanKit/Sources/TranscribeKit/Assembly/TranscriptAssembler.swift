import Foundation
import ProjectKit

/// Puts an engine's words and a detector's silences together into one transcript in spoken order.
///
/// - Each silence goes in the gap between the two words its middle falls between.
/// - A silence's edges are trusted over word times that run into it, since aligned times can be off.
/// - A word entirely inside a silence is real quiet speech, so the silence is split around it rather than
///   swallowing it. Words with no sound under them should already have been moved out of silences
///   (``WordFitter``), or they'd wrongly split the silence too.
/// - Fillers are marked, never removed.
public enum TranscriptAssembler {
    /// Silence left over after splitting around a quiet word is dropped when shorter than this.
    static let shortestSilencePiece: TimeInterval = 0.05

    public static func draft(
        words rawWords: [TimedWord],
        silences rawSilences: [TimeRange],
        duration: TimeInterval,
        engine: String,
        silenceDetector: String,
        language: String?
    ) -> TranscriptDraft {
        let words = clean(rawWords, duration: duration)
        let silences = split(rawSilences, around: words, duration: duration)

        // Gap g is the space before word g; gap words.count is after the last word.
        // A silence goes before the first word whose middle is at or past its own middle. Start times are
        // in order, but overlapping engine timings can put middles out of order, so the search runs over
        // the running maximum of the middles instead: that's in order, and it first reaches a time at the
        // same word the middles themselves first do.
        var reach = words.map { ($0.start + $0.end) / 2 }
        for index in reach.indices.dropFirst() {
            reach[index] = max(reach[index], reach[index - 1])
        }
        var silencesInGap = [[TimeRange]](repeating: [], count: words.count + 1)
        for silence in silences {
            let gap = firstIndex(in: reach, reaching: (silence.start + silence.end) / 2)
            silencesInGap[gap].append(silence)
        }

        var items: [TranscriptDraft.DraftItem] = []
        for gap in 0...words.count {
            for silence in silencesInGap[gap].sorted(by: { $0.start < $1.start }) {
                items.append(.silence(start: silence.start, end: silence.end))
            }
            if gap < words.count {
                let word = words[gap]
                items.append(
                    .word(
                        .init(
                            text: word.text,
                            start: word.start,
                            end: word.end,
                            confidence: word.confidence,
                            isFiller: FillerWords.isFiller(word.text)
                        )
                    )
                )
            }
        }
        return TranscriptDraft(
            engine: engine,
            silenceDetector: silenceDetector,
            language: language,
            audioDuration: duration,
            items: items
        )
    }

    /// Words trimmed, kept inside the audio, with no backwards times, in order of start.
    static func clean(_ words: [TimedWord], duration: TimeInterval) -> [TimedWord] {
        words.compactMap { word in
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let start = min(max(0, word.start), duration)
            let end = min(max(start, word.end), duration)
            return TimedWord(text: text, start: start, end: end, confidence: word.confidence)
        }
        .enumerated()
        .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
        .map(\.element)
    }

    /// Silences inside the audio, sorted, with any word that sits entirely inside one cut out of it.
    static func split(_ silences: [TimeRange], around words: [TimedWord], duration: TimeInterval) -> [TimeRange] {
        silences
            .map { TimeRange(start: max(0, $0.start), end: min(duration, $0.end)) }
            .filter { !$0.isEmpty }
            .sorted { $0.start < $1.start }
            .flatMap { silence -> [TimeRange] in
                var pieces = [silence]
                for word in words where word.start > silence.start && word.end < silence.end {
                    pieces = pieces.flatMap { $0.subtracting(TimeRange(start: word.start, end: word.end)) }
                }
                return pieces.filter { $0.duration >= shortestSilencePiece }
            }
    }

    /// The first index whose value is at or past `time`, in values that never decrease, or the count when
    /// there's none.
    private static func firstIndex(in values: [TimeInterval], reaching time: TimeInterval) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if values[middle] >= time {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}

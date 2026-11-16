import Foundation
import ProjectKit

/// Moves the transcription model's word times to fit the audio (docs/decisions.md, 74).
///
/// Parakeet's word times can be off by a few tenths of a second. On real takes the first word after a
/// pause is often timed 0.3–0.4 s early, inside the silence, with no sound under it, and the last word before
/// a pause often runs on into it. The silences come from the audio, so they win:
///
/// - **A word with no sound under it, inside a silence,** moves to the edge of the nearest stretch of sound.
///   The words over the next ``Settings/closingSpan`` close up behind it, squeezed in proportion, so their
///   order and rough lengths are kept.
/// - **A word that runs into a silence** is trimmed at the silence's edge.
/// - **A word with sound under it, inside a silence,** is real quiet speech and stays where it is; the
///   assembler splits the silence around it.
/// - **Where two words run together,** the edge between them moves to the quietest point within
///   ``Settings/boundaryReach``, when that's clearly quieter than where it was.
public enum WordFitter {
    public struct Settings: Sendable, Equatable {
        /// How much of the words after an early word close up behind it, in seconds of their own times.
        public var closingSpan: TimeInterval
        /// How far an edge between two words may move to a quieter point, in seconds: one of Parakeet's
        /// 80 ms frames.
        public var boundaryReach: TimeInterval
        /// How much quieter, in dB, a point must be than the edge where it is for the edge to move there.
        public var boundaryDepth: Double
        /// No word is made shorter than this.
        public var shortestWord: TimeInterval
        /// How much sound, in seconds above the threshold, makes a word inside a silence real quiet speech.
        public var heardSound: TimeInterval

        public init(closingSpan: TimeInterval = 1.0, boundaryReach: TimeInterval = 0.08, boundaryDepth: Double = 3,
                    shortestWord: TimeInterval = 0.04, heardSound: TimeInterval = 0.03) {
            self.closingSpan = closingSpan
            self.boundaryReach = boundaryReach
            self.boundaryDepth = boundaryDepth
            self.shortestWord = shortestWord
            self.heardSound = heardSound
        }

        /// For words the timing model has already placed (``WordTimer``; docs/decisions.md, 95): they're only
        /// kept out of silences. Nothing closes up behind a moved word and no edge moves to a quieter point,
        /// since those corrected Parakeet's own errors and, measured, moved some well-placed words
        /// (docs/bakeoff-findings.md).
        public static let afterTiming = Settings(closingSpan: 0, boundaryReach: 0)
    }

    /// The words, fitted to what the silence detector measured.
    public static func fit(_ words: [TimedWord], to analysis: EnergySilenceDetector.Analysis, settings: Settings = Settings()) -> [TimedWord] {
        fit(words, silences: analysis.silences, envelope: analysis.envelope, threshold: analysis.threshold,
            duration: analysis.duration, settings: settings)
    }

    /// The words, in order of start, fitted to the silences and loudness of the audio they came from.
    public static func fit(_ words: [TimedWord], silences: [TimeRange], envelope: SoundEnvelope, threshold: Double,
                           duration: TimeInterval, settings: Settings = Settings()) -> [TimedWord] {
        var fitted = words.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        let runs = soundRuns(between: silences, duration: duration)
        guard !runs.isEmpty else { return fitted }

        // Each word belongs to the stretch of sound it overlaps most. One with no sound under it, inside a
        // silence, belongs to the nearest; one with sound under it there belongs to none and stays put.
        var members = [[Int]](repeating: [], count: runs.count)
        for (index, word) in fitted.enumerated() {
            let overlaps = runs.map { min($0.end, word.end) - max($0.start, word.start) }
            if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
                members[best].append(index)
            } else if !isHeard(word, envelope: envelope, threshold: threshold, settings: settings),
                let nearest = runs.indices.min(by: { distance(from: word, to: runs[$0]) < distance(from: word, to: runs[$1]) })
            {
                members[nearest].append(index)
            }
        }

        for (run, indices) in zip(runs, members) where !indices.isEmpty {
            // Early words close up after the start of the sound.
            let first = indices.map { fitted[$0].start }.min() ?? run.start
            let early = run.start - first
            let span = settings.closingSpan
            func closed(_ time: TimeInterval) -> TimeInterval {
                guard early > 0, time < run.start + span else { return time }
                return run.start + (time - first) * span / (span + early)
            }
            for index in indices {
                var start = max(run.start, closed(fitted[index].start))
                var end = min(run.end, closed(fitted[index].end))
                if end < start + settings.shortestWord {
                    end = min(run.end, start + settings.shortestWord)
                    start = max(run.start, min(start, end - settings.shortestWord))
                }
                fitted[index].start = start
                fitted[index].end = max(start, end)
            }
            // Edges between words that run together move to the quietest point near them.
            for (a, b) in zip(indices, indices.dropFirst()) {
                let left = fitted[a], right = fitted[b]
                guard abs(right.start - left.end) <= 0.02 else { continue }
                let edge = (left.end + right.start) / 2
                let reach = TimeRange(start: max(edge - settings.boundaryReach, left.start + settings.shortestWord),
                                      end: min(edge + settings.boundaryReach, right.end - settings.shortestWord))
                guard reach.end > reach.start, let quiet = envelope.quietest(in: reach, near: edge),
                    let quietLevel = envelope.smoothedLevel(at: quiet), let edgeLevel = envelope.smoothedLevel(at: edge),
                    quietLevel <= edgeLevel - settings.boundaryDepth
                else { continue }
                fitted[a].end = quiet
                fitted[b].start = quiet
            }
        }
        return fitted
    }

    /// The stretches of sound between silences, in order.
    static func soundRuns(between silences: [TimeRange], duration: TimeInterval) -> [TimeRange] {
        var runs: [TimeRange] = []
        var position: TimeInterval = 0
        for silence in silences.sorted(by: { $0.start < $1.start }) {
            if silence.start > position { runs.append(TimeRange(start: position, end: silence.start)) }
            position = max(position, silence.end)
        }
        if position < duration { runs.append(TimeRange(start: position, end: duration)) }
        return runs
    }

    /// Whether there's enough sound under a word to call it speech.
    static func isHeard(_ word: TimedWord, envelope: SoundEnvelope, threshold: Double, settings: Settings) -> Bool {
        guard let frames = envelope.frames(in: TimeRange(start: word.start, end: max(word.start, word.end))) else { return false }
        let loud = frames.filter { envelope.levels[$0] >= threshold }.count
        return Double(loud) * envelope.frameDuration >= settings.heardSound - 1e-9
    }

    private static func distance(from word: TimedWord, to run: TimeRange) -> TimeInterval {
        if run.start >= word.end { return run.start - word.end }
        if run.end <= word.start { return word.start - run.end }
        return 0
    }
}

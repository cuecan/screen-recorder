import Foundation

/// Laying fixes over a transcript (docs/decisions.md, 69).
extension Transcript {
    /// The transcript with a fix laid over it, or nil if the fix's words aren't in it.
    ///
    /// The replaced words go, and the fix's words take their place. New words keep between the words either
    /// side of the run, so they never cross them. Silences stay real silences: one a new word overlaps
    /// keeps its longest stretch clear of every new word, and goes if that's under ``minimumSilence``.
    /// Retakes and second readings that named a replaced word go with it.
    public func applying(_ fix: WordFix) -> Transcript? {
        guard case .word = fix.replaces.first, case .word = fix.replaces.last,
              let from = index(of: fix.replaces.first), let to = index(of: fix.replaces.last), from <= to,
              !fix.words.isEmpty
        else { return nil }
        let earliest = items[..<from].last { !$0.isSilence }?.end ?? 0
        let latest = items[(to + 1)...].first { !$0.isSilence }?.start ?? max(audioDuration, items.last?.end ?? 0)
        let newWords = fix.words.map { word -> Word in
            var word = word
            word.start = min(max(word.start, earliest), latest)
            word.end = min(max(word.end, word.start), latest)
            return word
        }
        let spans = newWords.map { TimeRange(start: $0.start, end: $0.end) }
        let removed = Set(items[from...to].compactMap { item -> WordID? in if case .word(let word) = item { word.id } else { nil } })

        var kept: [TranscriptItem] = []
        for (index, item) in items.enumerated() {
            if index == from { kept.append(contentsOf: newWords.map(TranscriptItem.word)) }
            switch item {
            case .word where (from...to).contains(index):
                continue
            case .silence(let silence) where silence.end > earliest && silence.start < latest:
                if let clear = Self.longestClearStretch(of: silence, avoiding: spans) { kept.append(.silence(clear)) }
            default:
                kept.append(item)
            }
        }
        var transcript = self
        // Clamping can put a corrected word exactly on the following word's start. Keep reading order
        // at equal times, so a late alignment never moves the final corrected word after its neighbour.
        transcript.items = kept.enumerated().sorted {
            let left = ($0.element.start, $0.element.isSilence ? 0 : 1, $0.offset)
            let right = ($1.element.start, $1.element.isSilence ? 0 : 1, $1.offset)
            return left < right
        }.map(\.element)
        func survives(_ range: ItemRange) -> Bool {
            guard let start = index(of: range.first), let end = index(of: range.last), start <= end else { return false }
            return items[start...end].allSatisfy { item in
                if case .word(let word) = item { !removed.contains(word.id) } else { true }
            }
        }
        transcript.retakes = retakes.filter { survives($0.attempt) && survives($0.redoneAs) }
        transcript.alternatives = alternatives.filter { survives($0.words) }
        return transcript
    }

    /// The shortest silence a fix leaves in place, in seconds. Anything shorter is no use to cut in.
    public static let minimumSilence: TimeInterval = 0.03

    /// The longest part of a silence that no word overlaps, keeping its id; nil if that's too short.
    static func longestClearStretch(of silence: Silence, avoiding spans: [TimeRange]) -> Silence? {
        var pieces = [TimeRange(start: silence.start, end: silence.end)]
        for span in spans where span.end > silence.start && span.start < silence.end {
            pieces = pieces.flatMap { piece -> [TimeRange] in
                guard span.end > piece.start, span.start < piece.end else { return [piece] }
                return [TimeRange(start: piece.start, end: span.start), TimeRange(start: span.end, end: piece.end)]
                    .filter { $0.end > $0.start }
            }
        }
        guard let longest = pieces.max(by: { $0.duration < $1.duration }), longest.duration >= minimumSilence else { return nil }
        return Silence(id: silence.id, start: longest.start, end: longest.end)
    }
}

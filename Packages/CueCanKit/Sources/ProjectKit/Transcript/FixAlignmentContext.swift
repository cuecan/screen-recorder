import Foundation

/// The known words and audio window for timing a correction. Keeps source time and file time together,
/// including a mic that starts after the beginning of its recording.
public struct FixAlignmentContext: Equatable, Sendable {
    public let text: String
    public let correctedWords: Range<Int>
    public let sourceRange: TimeRange
    public let fileRange: TimeRange

    public init?(transcript: Transcript, replacing range: ItemRange, text: String,
                 audioRange: TimeRange, context: TimeInterval, padding: TimeInterval) throws(EditError) {
        let indices = try CutPointSnapper(transcript: transcript).indices(of: range)
        let items = transcript.items
        let start = items[indices.lowerBound].start, end = items[indices.upperBound].end
        let before = items[..<indices.lowerBound].compactMap { item -> Word? in
            if case .word(let word) = item, word.start >= start - context { word } else { nil }
        }
        let after = items[(indices.upperBound + 1)...].compactMap { item -> Word? in
            if case .word(let word) = item, word.end <= end + context { word } else { nil }
        }
        let corrected = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !corrected.isEmpty else { return nil }
        let from = max(audioRange.start, 0, (before.first?.start ?? start) - padding)
        let to = min(audioRange.end, transcript.audioDuration, (after.last?.end ?? end) + padding)
        guard from.isFinite, to.isFinite, to > from else { return nil }
        // An untimed earlier fix is one transcript item holding several words. The aligner splits
        // whitespace, so indices must count spoken words rather than transcript items.
        let leading = before.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
        let trailing = after.flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(String.init) }
        self.text = (leading + corrected + trailing).joined(separator: " ")
        correctedWords = leading.count..<(leading.count + corrected.count)
        sourceRange = TimeRange(start: from, end: to)
        fileRange = TimeRange(start: from - audioRange.start, end: to - audioRange.start)
    }
}

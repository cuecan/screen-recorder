import Foundation
import ProjectKit

/// Splits a long recording into pieces a model can take at once, cutting inside silences so no word is
/// split between two pieces.
public enum AudioChunker {
    /// Pieces that cover `0..<duration` back to back, none longer than `maximumDuration`.
    ///
    /// Each cut goes in the middle of the longest silence in the second half of the allowed length. When
    /// there's no silence there, the piece is cut at the maximum length.
    public static func chunks(
        duration: TimeInterval,
        silences: [TimeRange],
        maximumDuration: TimeInterval
    ) -> [TimeRange] {
        guard duration > 0 else { return [] }
        guard maximumDuration > 0 else { return [TimeRange(start: 0, end: duration)] }

        var chunks: [TimeRange] = []
        var start = 0.0
        while duration - start > maximumDuration {
            let window = TimeRange(start: start + maximumDuration / 2, end: start + maximumDuration)
            let best = silences
                .map { TimeRange(start: max($0.start, window.start), end: min($0.end, window.end)) }
                .filter { !$0.isEmpty }
                .max { $0.duration < $1.duration }
            let cut = best.map { ($0.start + $0.end) / 2 } ?? window.end
            chunks.append(TimeRange(start: start, end: cut))
            start = cut
        }
        chunks.append(TimeRange(start: start, end: duration))
        return chunks
    }
}

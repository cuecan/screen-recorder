import Foundation
import ProjectKit

/// Turns the speech a voice activity model finds into the silences between it.
enum SpeechGaps {
    /// The stretches of `0..<duration` not covered by any of `speech`, at least `minimum` long.
    static func silences(between speech: [TimeRange], duration: TimeInterval, minimum: TimeInterval) -> [TimeRange] {
        var gaps: [TimeRange] = []
        var cursor = 0.0
        for segment in speech.sorted(by: { $0.start < $1.start }) {
            if segment.start - cursor >= minimum {
                gaps.append(TimeRange(start: cursor, end: segment.start))
            }
            cursor = max(cursor, segment.end)
        }
        if duration - cursor >= minimum {
            gaps.append(TimeRange(start: cursor, end: duration))
        }
        return gaps
    }
}

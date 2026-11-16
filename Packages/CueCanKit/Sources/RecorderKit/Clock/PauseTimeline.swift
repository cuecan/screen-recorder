import Foundation

/// Takes paused stretches out of a recording's clock, the same way for every track, so the tracks stay in
/// sync across a pause.
///
/// Times are host-clock seconds. A sample captured during a pause is dropped; one captured after it moves
/// earlier by everything paused before it.
public struct PauseTimeline: Sendable, Equatable {
    private var pauses: [(start: TimeInterval, end: TimeInterval?)] = []

    public init() {}

    public var isPaused: Bool { pauses.last.map { $0.end == nil } ?? false }

    public mutating func pause(at time: TimeInterval) {
        guard !isPaused else { return }
        pauses.append((time, nil))
    }

    public mutating func resume(at time: TimeInterval) {
        guard isPaused, let last = pauses.indices.last else { return }
        pauses[last].end = max(time, pauses[last].start)
    }

    /// The time with earlier pauses taken out, or nil if it falls inside one.
    public func adjusted(_ time: TimeInterval) -> TimeInterval? {
        var removed: TimeInterval = 0
        for pause in pauses {
            guard time >= pause.start else { break }
            guard let end = pause.end, time >= end else { return nil }
            removed += end - pause.start
        }
        return time - removed
    }

    /// The time with pauses taken out, holding still during a pause: what a recording timer shows.
    public func elapsed(at time: TimeInterval) -> TimeInterval {
        var removed: TimeInterval = 0
        for pause in pauses {
            guard time >= pause.start else { break }
            guard let end = pause.end, time >= end else { return pause.start - removed }
            removed += end - pause.start
        }
        return time - removed
    }

    /// The total paused so far.
    public var pausedDuration: TimeInterval {
        pauses.reduce(0) { $0 + (($1.end ?? $1.start) - $1.start) }
    }

    public static func == (lhs: PauseTimeline, rhs: PauseTimeline) -> Bool {
        lhs.pauses.elementsEqual(rhs.pauses) { $0.start == $1.start && $0.end == $1.end }
    }
}

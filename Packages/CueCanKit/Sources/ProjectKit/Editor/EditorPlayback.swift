import Foundation

/// Playback intent, independent of the player's temporary pauses while replacing or buffering an item.
public struct EditorPlayback: Equatable, Sendable {
    public enum State: Equatable, Sendable { case paused, playing(rate: Float) }
    public enum Direction: Sendable { case backward, forward }
    public private(set) var state: State = .paused

    public init() {}
    public var rate: Float { if case .playing(let rate) = state { rate } else { 0 } }
    public var isPlaying: Bool { state != .paused }
    public mutating func play() { state = .playing(rate: 1) }
    public mutating func pause() { state = .paused }

    /// Repeated J or L doubles speed to 8×; changing direction starts at 1×.
    public mutating func shuttle(_ direction: Direction) {
        let step: Float = direction == .forward ? 1 : -1
        let next = rate == 0 || (rate > 0) != (step > 0) ? step : min(max(rate * 2, -8), 8)
        state = .playing(rate: next)
    }
}

import Foundation

/// Whether the camera is actually sending a picture, apart from AVFoundation so it can be tested.
///
/// A capture session can be running while the camera sends nothing: the Studio Display's camera, started
/// again quickly after a stop, sometimes streams packets that never decode into a frame (seen in
/// UVCAssistant's log: 281,248 packets, 0 frames, for 35 s). The session reports nothing wrong. So the
/// camera counts as on only while frames arrive; when none come for ``quiet``, it's started again, up to
/// ``restarts`` times, and then it's given up on, with a reason.
public struct CameraFrameWatch: Sendable, Equatable {
    /// A restart owns a token until capture has actually restarted. A late completion cannot finish
    /// another restart, and time spent restarting does not consume the next waiting period.
    public enum State: Sendable, Equatable {
        case waiting
        case delivering
        case restarting(UUID)
        case failed
    }
    public private(set) var state: State = .waiting
    public var hasPicture: Bool { state == .delivering }
    /// How long the camera can send nothing before it's started again.
    public static let quiet: TimeInterval = 2.5
    /// How many times it's started again before CueCan says it isn't sending a picture.
    public static let restarts = 2

    public enum Verdict: Sendable, Equatable {
        /// Frames are arriving.
        case delivering
        /// No frame yet, but it hasn't been long.
        case waiting
        /// Nothing for too long: start the camera again.
        case restart(UUID)
        /// Started again and still nothing.
        case failed
    }

    /// When the camera was last started, in seconds of system uptime.
    public private(set) var startedAt: TimeInterval
    /// How many times it has been started again since it was chosen.
    public private(set) var restartCount = 0

    public init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    /// What to do now, given when the last frame arrived (nil for none since the camera started).
    public mutating func check(lastFrame: TimeInterval?, now: TimeInterval) -> Verdict {
        switch state {
        case .restarting: return .waiting
        case .failed: return .failed
        case .waiting, .delivering: break
        }
        if let lastFrame, lastFrame >= startedAt, now - lastFrame <= Self.quiet {
            state = .delivering
            return .delivering
        }
        let since = max(lastFrame ?? startedAt, startedAt)
        if now - since < Self.quiet {
            state = .waiting
            return .waiting
        }
        guard restartCount < Self.restarts else {
            state = .failed
            return .failed
        }
        let request = UUID()
        restartCount += 1
        state = .restarting(request)
        return .restart(request)
    }

    /// Capture finished restarting at `time`. Only the matching restart can start a new waiting period.
    @discardableResult
    public mutating func restartFinished(_ request: UUID, at time: TimeInterval) -> Bool {
        guard state == .restarting(request) else { return false }
        startedAt = time
        state = .waiting
        return true
    }
}

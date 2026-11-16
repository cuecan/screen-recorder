import CoreMedia
import Foundation

/// The one clock every track of a recording is placed on: the Mac's host clock, from when Record was
/// pressed, with pauses taken out.
///
/// Screen and system-audio buffers arrive stamped on the host clock; camera and mic buffers on their
/// capture session's clock, which is converted. Each track remembers its first time, so the source can
/// line the tracks up by their offsets (docs/design.md, "Recording the screen and camera").
public final class RecordingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var origin: TimeInterval?
    private var pauses = PauseTimeline()

    public init() {}

    /// The host clock now, in seconds.
    public static var hostNow: TimeInterval { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    /// Starts the recording's clock. Buffers stamped earlier are dropped.
    public func start(at time: TimeInterval = RecordingClock.hostNow) {
        lock.withLock { origin = time }
    }

    public func pause(at time: TimeInterval = RecordingClock.hostNow) {
        lock.withLock { pauses.pause(at: time) }
    }

    public func resume(at time: TimeInterval = RecordingClock.hostNow) {
        lock.withLock { pauses.resume(at: time) }
    }

    public var isPaused: Bool { lock.withLock { pauses.isPaused } }

    /// How long has been recorded, pauses left out. It holds still while paused.
    public var elapsed: TimeInterval { elapsed(at: Self.hostNow) }

    public func elapsed(at time: TimeInterval) -> TimeInterval {
        lock.withLock {
            guard let origin else { return 0 }
            return max(0, pauses.elapsed(at: time) - origin)
        }
    }

    /// Where a host-clock time lands in the recording, or nil before it started or during a pause.
    public func place(_ hostTime: TimeInterval) -> TimeInterval? {
        lock.withLock {
            guard let origin, hostTime >= origin, let adjusted = pauses.adjusted(hostTime) else { return nil }
            return adjusted - origin
        }
    }

    /// A buffer's presentation time on the host clock.
    static func hostTime(of buffer: CMSampleBuffer, from clock: CMClock?) -> TimeInterval {
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard let clock else { return time.seconds }
        return CMSyncConvertTime(time, from: clock, to: CMClockGetHostTimeClock()).seconds
    }
}

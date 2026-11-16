import Foundation
import Synchronization

/// At most one pending UI delivery. Camera capture never waits for a preview to draw, and a busy UI
/// receives the newest image instead of retaining a queue of old pixel buffers.
public final class CameraPreviewDelivery: Sendable {
    public struct Update: Sendable { public let frame: CameraPreviewFrame? }
    private struct Pending {
        var update: Update?
        var scheduled = false
        var lastTime: TimeInterval = -.infinity
    }
    private let pending = Mutex(Pending())
    public init() {}

    /// True when the caller needs to schedule a delivery. Nil clears the displayed image.
    public func submit(_ frame: CameraPreviewFrame?) -> Bool {
        pending.withLock { value in
            if let frame {
                guard frame.hostTime >= value.lastTime else { return false }
                value.lastTime = frame.hostTime
            }
            value.update = Update(frame: frame)
            guard !value.scheduled else { return false }
            value.scheduled = true
            return true
        }
    }

    public func take() -> Update? {
        pending.withLock { value in
            defer { value.update = nil; value.scheduled = false }
            return value.update
        }
    }
}

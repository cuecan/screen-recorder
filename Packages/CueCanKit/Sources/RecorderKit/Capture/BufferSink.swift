import CoreMedia
import Foundation

/// Where a capture sends its buffers while recording, swapped in and out from any thread.
final class BufferSink: @unchecked Sendable {
    typealias Receive = @Sendable (CMSampleBuffer, TimeInterval) -> Void
    private let lock = NSLock()
    private var receive: Receive?

    func set(_ receive: Receive?) {
        lock.withLock { self.receive = receive }
    }

    func send(_ buffer: CMSampleBuffer, hostTime: TimeInterval) {
        lock.withLock { receive?(buffer, hostTime) }
    }
}

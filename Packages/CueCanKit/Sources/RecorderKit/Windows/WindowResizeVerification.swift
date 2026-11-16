import CoreGraphics
import Foundation

/// Resizing another app can settle after its Accessibility reply. Read after yielding and retry before
/// reporting a size constraint; cancellation stops further writes from an obsolete area or closed setup.
enum WindowResizeVerification {
    enum Match: Sendable { case frame, size }

    static func settle(to target: CGRect,
                       resize: @Sendable (CGRect) async -> Void,
                       read: @Sendable () async -> CGRect?,
                       matching: Match = .frame,
                       pause: @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(80)) }) async throws -> CGRect? {
        try Task.checkCancellation()
        await resize(target)
        var latest: CGRect?
        for poll in 0..<8 {
            try await pause()
            try Task.checkCancellation()
            if let frame = await read() {
                latest = frame
                let matches = switch matching {
                case .frame: WindowFit.fills(frame, area: target)
                case .size: WindowFit.fit(result: frame.size, area: target.size) == .fits
                }
                if matches { return frame }
            }
            if poll == 1 || poll == 4 {
                try Task.checkCancellation()
                await resize(target)
            }
        }
        return latest
    }
}

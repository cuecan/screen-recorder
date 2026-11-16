import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import IOSurface
import ScreenCaptureKit

/// A light live picture of the capture area, for the Recording Panel's Full preview (docs/ui.md, R6).
///
/// It's its own `SCStream`, separate from the recording's, kept cheap: the area scaled down so its longer
/// side is at most ``maximumPixels``, at ``frameRate`` frames a second, with no audio and CueCan's own
/// windows left out. It runs only while a Full panel is on screen, and only once Screen Recording access
/// has been given, so it never brings up the permission prompt by itself.
public final class AreaPreview: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public static let frameRate = 10
    public static let maximumPixels = 640.0

    private let stream: SCStream
    private let queue = DispatchQueue(label: "CueCan.AreaPreview")
    private let lock = NSLock()
    private var receive: (@Sendable (IOSurfaceRef) -> Void)?
    private var delivered = 0

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration) {
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        super.init()
    }

    /// Frames delivered so far, for measuring what the preview costs.
    public var framesDelivered: Int { lock.withLock { delivered } }

    /// Sets what receives each frame's surface, on a background queue.
    public func onFrame(_ receive: (@Sendable (IOSurfaceRef) -> Void)?) {
        lock.withLock { self.receive = receive }
    }

    /// Starts a preview of an area of a display.
    ///
    /// - Parameter area: The area in the display's own points, from its top left
    ///   (``AreaGeometry/sourceRect(for:onDisplay:)``).
    public static func start(displayID: CGDirectDisplayID, area: CGRect) async throws -> AreaPreview {
        guard ScreenCapture.hasPermission else { throw RecorderError.noScreenRecordingPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw RecorderError.displayNotFound }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let preview = AreaPreview(filter: filter, configuration: configuration(for: area))
        try preview.stream.addStreamOutput(preview, type: .screen, sampleHandlerQueue: preview.queue)
        try await preview.stream.startCapture()
        return preview
    }

    /// Follows the area as it moves or changes size. Throws when the stream refuses the new crop, which it
    /// then keeps showing the old one.
    public func update(area: CGRect) async throws {
        try await stream.updateConfiguration(Self.configuration(for: area))
    }

    public func stop() async {
        onFrame(nil)
        try? await stream.stopCapture()
    }

    /// The preview's size in pixels: the area scaled so its longer side is at most ``maximumPixels``.
    public static func pixelSize(for area: CGSize) -> CGSize {
        let scale = min(1, maximumPixels / max(area.width, area.height, 1))
        return CGSize(width: max(2, (area.width * scale).rounded()), height: max(2, (area.height * scale).rounded()))
    }

    private static func configuration(for area: CGRect) -> SCStreamConfiguration {
        let size = pixelSize(for: area.size)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.capturesAudio = false
        return configuration
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
            let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
            let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue()
        else { return }
        let receive = lock.withLock {
            delivered += 1
            return self.receive
        }
        receive?(surface)
    }
}

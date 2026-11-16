import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// The screen area, and the Mac's system audio, through ScreenCaptureKit.
///
/// It captures one display, cropped to the area with `sourceRect`, at the display's native resolution, and
/// leaves CueCan's own windows out, so the widget can sit over the display being recorded
/// (docs/design.md, "Recording the screen and camera"). The frame and dimming sit outside the area anyway.
///
/// The display comes from where the area is placed. Choosing it through Apple's picker
/// (`SCContentSharingPicker`) instead, to avoid the monthly permission prompt, is VERIFY: it isn't
/// confirmed that `sourceRect` and leaving out the app's windows work with the picker's filter.
public final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public static let frameRate = 60

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "CueCan.ScreenCapture.video")
    private let audioQueue = DispatchQueue(label: "CueCan.ScreenCapture.audio")
    let videoSink = BufferSink()
    let audioSink = BufferSink()
    /// The stream stopped by itself, such as when the display was disconnected.
    public var onStop: (@Sendable (String) -> Void)?

    public let capturesSystemAudio: Bool
    /// The area's size in pixels.
    public let pixelSize: CGSize

    private init(stream: SCStream?, capturesSystemAudio: Bool, pixelSize: CGSize) {
        self.capturesSystemAudio = capturesSystemAudio
        self.pixelSize = pixelSize
        super.init()
    }

    /// Whether the Screen Recording permission is granted, without asking.
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks for the Screen Recording permission. macOS shows its prompt once; after that, the switch is in
    /// System Settings.
    @discardableResult
    public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Sets up a capture of an area of a display.
    ///
    /// - Parameters:
    ///   - displayID: The display the area is on.
    ///   - area: The area in the display's own points, from its top left (``AreaGeometry/sourceRect(for:onDisplay:)``).
    public static func make(displayID: CGDirectDisplayID, area: CGRect, capturesSystemAudio: Bool) async throws -> ScreenCapture {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecorderError.noScreenRecordingPermission
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw RecorderError.displayNotFound }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier || $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let scale = Double(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area
        configuration.width = Int((area.width * scale).rounded())
        configuration.height = Int((area.height * scale).rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.capturesAudio = capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1

        let capture = ScreenCapture(stream: nil, capturesSystemAudio: capturesSystemAudio, pixelSize: CGSize(width: configuration.width, height: configuration.height))
        let stream = SCStream(filter: filter, configuration: configuration, delegate: capture)
        try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.videoQueue)
        if capturesSystemAudio {
            try stream.addStreamOutput(capture, type: .audio, sampleHandlerQueue: capture.audioQueue)
        }
        capture.stream = stream
        return capture
    }

    public func start() async throws {
        try await stream?.startCapture()
    }

    public func stop() async {
        try? await stream?.stopCapture()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        let hostTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        switch type {
        case .screen:
            // Only frames with new content; idle and blank frames carry no picture.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete
            else { return }
            videoSink.send(sampleBuffer, hostTime: hostTime)
        case .audio:
            audioSink.send(sampleBuffer, hostTime: hostTime)
        default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop?(error.localizedDescription)
    }
}

import AVFoundation
import CoreImage
import Foundation
import Synchronization

/// The camera, live from the moment the widget opens, so its preview proves it works before recording.
///
/// Previews receive the output's existing pixel buffers. While recording, the same frames go to the
/// camera's file; opening or changing a preview never adds a capture connection.
public final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "CueCan.CameraCapture")
    let sink = BufferSink()
    public private(set) var device: CaptureDevice?
    /// The camera's frame rate, for the encoder.
    public private(set) var frameRate = 30
    /// The selected camera format's dimensions. Used for live crops instead of assuming a 16:9 camera.
    public private(set) var pictureSize = CGSize(width: 1920, height: 1080)
    /// When the last frame arrived, in seconds of system uptime, since the camera was last started.
    private let lastFrame = Mutex<TimeInterval?>(nil)

    /// When the last frame arrived since the camera was last started, in seconds of system uptime. Nil when
    /// none has (``CameraFrameWatch``).
    public var lastFrameTime: TimeInterval? { lastFrame.withLock { $0 } }
    /// Callers waiting for the next frame as a picture (``nextPicture()``).
    private let pictureRequests = Mutex<[CheckedContinuation<CGImage?, Never>]>([])
    private let pictureContext = CIContext(options: [.cacheIntermediates: false])
    private struct Preview {
        var frame: CameraPreviewFrame?
        var receive: (@Sendable (CameraPreviewFrame?) -> Void)?
    }
    private let preview = Mutex(Preview())

    /// Observes the same images that go to the writer, without adding an AVCapture connection. The
    /// callback must return promptly; UI consumers coalesce deliveries with `CameraPreviewDelivery`.
    public func onPreviewFrame(_ receive: @escaping @Sendable (CameraPreviewFrame?) -> Void) {
        let frame = preview.withLock { value in value.receive = receive; return value.frame }
        receive(frame)
    }

    private func showPreview(_ frame: CameraPreviewFrame?) {
        let receive = preview.withLock { value in value.frame = frame; return value.receive }
        receive?(frame)
    }

    public override init() {
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// Switches to a camera and starts it.
    public func use(_ choice: CaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    showPreview(nil)
                    try configure(choice)
                    lastFrame.withLock { $0 = nil }
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning else {
                        throw RecorderError.couldNotUseDevice(choice.name, "capture couldn't start")
                    }
                    continuation.resume()
                } catch {
                    if session.isRunning { session.stopRunning() }
                    device = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure(_ choice: CaptureDevice) throws {
        guard let camera = AVCaptureDevice(uniqueID: choice.id) else { throw RecorderError.noCamera }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            throw RecorderError.couldNotUseDevice(choice.name, error.localizedDescription)
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        for old in session.inputs { session.removeInput(old) }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecorderError.couldNotUseDevice(choice.name, "it's in use by another app, or doesn't offer video.")
        }
        session.addInput(input)
        if session.outputs.isEmpty {
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw RecorderError.couldNotUseDevice(choice.name, "capture couldn't receive its samples")
            }
            session.addOutput(output)
        }
        session.commitConfiguration()
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        pictureSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        let maximum = camera.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        frameRate = min(60, max(24, Int(maximum.rounded())))
        device = choice
    }

    public func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            showPreview(nil)
        }
        answerPictureRequests(with: nil)
    }

    /// The camera's next frame as a picture, unmirrored, such as for finding the creator's face while
    /// setting up (docs/decisions.md, 78). Nil if the camera stops first.
    public func nextPicture() async -> CGImage? {
        await withCheckedContinuation { continuation in
            pictureRequests.withLock { $0.append(continuation) }
        }
    }

    private func answerPictureRequests(with picture: CGImage?) {
        let requests = pictureRequests.withLock { requests in
            defer { requests.removeAll() }
            return requests
        }
        for request in requests { request.resume(returning: picture) }
    }

    /// Stops the camera and starts it again, for a camera that's running but sending no picture.
    public func restart() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                lastFrame.withLock { $0 = nil }
                session.startRunning()
                continuation.resume()
            }
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        lastFrame.withLock { $0 = now }
        if let pixels = CMSampleBufferGetImageBuffer(sampleBuffer), let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            showPreview(CameraPreviewFrame(pixels: pixels, format: format, hostTime: now))
        }
        if pictureRequests.withLock({ !$0.isEmpty }), let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let image = CIImage(cvPixelBuffer: pixels)
            answerPictureRequests(with: pictureContext.createCGImage(image, from: image.extent))
        }
        sink.send(sampleBuffer, hostTime: RecordingClock.hostTime(of: sampleBuffer, from: session.synchronizationClock))
    }
}

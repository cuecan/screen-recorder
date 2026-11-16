import AVFoundation
import Foundation

/// The mic, through AVFoundation rather than ScreenCaptureKit (docs/decisions.md, 16), as raw 48 kHz mono float.
///
/// Its levels come from the very buffers that are written to the mic file, so the waveform proves what's
/// recorded (docs/decisions.md, 18). If the device disappears, it says so: it never switches to another mic.
public final class MicCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    public static let sampleRate = 48_000.0

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "CueCan.MicCapture")
    let sink = BufferSink()
    private var analyzer = LevelAnalyzer(sampleRate: MicCapture.sampleRate)
    private var disconnectObserver: (any NSObjectProtocol)?
    public private(set) var device: CaptureDevice?

    /// New levels, about every 20 ms, on the capture queue.
    public var onLevels: (@Sendable ([LevelSample]) -> Void)?
    /// The mic in use was unplugged or stopped working.
    public var onDisconnect: (@Sendable (CaptureDevice) -> Void)?

    public override init() {
        super.init()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// Switches to a mic and starts it.
    public func use(_ choice: CaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try configure(choice)
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
        guard let mic = AVCaptureDevice(uniqueID: choice.id) else { throw RecorderError.noMicrophone }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: mic)
        } catch {
            throw RecorderError.couldNotUseDevice(choice.name, error.localizedDescription)
        }
        session.beginConfiguration()
        for old in session.inputs { session.removeInput(old) }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecorderError.couldNotUseDevice(choice.name, "it's in use, or doesn't offer sound.")
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
        device = choice

        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: mic, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.onDisconnect?(choice)
        }
    }

    public func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    deinit {
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let samples = Self.floats(in: sampleBuffer)
        let levels = analyzer.append(samples)
        if !levels.isEmpty { onLevels?(levels) }
        sink.send(sampleBuffer, hostTime: RecordingClock.hostTime(of: sampleBuffer, from: session.synchronizationClock))
    }

    /// The mono float samples in a buffer delivered with ``MicCapture``'s settings.
    static func floats(in buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        samples.withUnsafeMutableBytes { bytes in
            if let base = bytes.baseAddress { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base) }
        }
        return samples
    }
}

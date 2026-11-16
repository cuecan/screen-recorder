import AVFoundation
import RecorderKit

/// The hardware boundary of calibration, replaceable in lifecycle tests.
@MainActor
protocol SyncCalibrationCapture: AnyObject {
    func start(camera: CaptureDevice, mic: CaptureDevice) async throws
    func stop()
    func measurement() async -> SyncMeasurement
    var cameraIsUnreadable: Bool { get }
    /// The camera's picture while it runs, or nil where there's none to show.
    var preview: CameraPreviewFeed? { get }
}

extension SyncCalibrationCapture {
    var preview: CameraPreviewFeed? { nil }
}

/// Owns the camera, mic and their taps together. A cancelled start still has to finish before another
/// start can use these devices; the model keeps that shutdown ordering.
final class DeviceSyncCalibrationCapture: SyncCalibrationCapture {
    private let camera = CameraCapture()
    private let mic = MicCapture()
    private lazy var calibrator = SyncCalibrator(camera: camera, mic: mic)
    private(set) lazy var preview: CameraPreviewFeed? = CameraPreviewFeed(camera: camera)

    func start(camera choice: CaptureDevice, mic microphone: CaptureDevice) async throws {
        guard await CaptureDevices.requestAccess(for: .video) else { throw AccessDenied() }
        try Task.checkCancellation()
        guard await CaptureDevices.requestAccess(for: .audio) else { throw AccessDenied() }
        try Task.checkCancellation()
        try await camera.use(choice)
        try Task.checkCancellation()
        try await mic.use(microphone)
        try Task.checkCancellation()
        calibrator.start()
    }

    func stop() {
        calibrator.stop()
        camera.stop()
        mic.stop()
    }

    func measurement() async -> SyncMeasurement {
        let calibrator = calibrator
        return await Task.detached { calibrator.measurement() }.value
    }

    var cameraIsUnreadable: Bool { calibrator.cameraIsUnreadable }

    private struct AccessDenied: LocalizedError {
        var errorDescription: String? {
            "Allow the camera and the mic in System Settings."
        }
    }
}

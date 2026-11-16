import Foundation
import Observation
import RecorderKit

/// Lip sync for new recordings: how far the camera runs behind the mic, for the camera and mic the last
/// setup used, set by hand or measured from the sync page's flashes and beeps (docs/decisions.md, 83).
/// The measuring is RecorderKit's (`SyncCalibrator`); this starts the camera and the mic a recording would
/// use, listens until five readings agree, and saves the result for that pair without asking.
@Observable final class SyncCalibrationModel {
    /// How long to listen before giving up, in seconds. A starting value.
    static let patience: TimeInterval = 180

    private var progress = SyncCalibrationProgress()
    var stage: SyncCalibrationProgress.State { progress.state }
    private(set) var camera: CaptureDevice?
    private(set) var mic: CaptureDevice?
    /// What's remembered for this camera and mic.
    private(set) var saved: SyncCalibrations.Calibration?

    @ObservationIgnored private let capture: any SyncCalibrationCapture
    @ObservationIgnored private var run: Task<Void, Never>?

    init() {
        capture = DeviceSyncCalibrationCapture()
        refresh()
    }

    init(camera: CaptureDevice, mic: CaptureDevice, capture: any SyncCalibrationCapture) {
        self.camera = camera
        self.mic = mic
        self.capture = capture
    }

    /// The camera and the mic a recording's setup would open on, and what's remembered for them.
    func refresh() {
        (camera, mic) = Self.rememberedDevices()
        saved = Self.remembered(camera: camera, mic: mic)
    }

    /// The camera and mic last chosen in a setup, or the Mac's own when none has been.
    static func rememberedDevices() -> (camera: CaptureDevice?, mic: CaptureDevice?) {
        let defaults = UserDefaults.standard
        let cameras = CaptureDevices.cameras, microphones = CaptureDevices.microphones
        let camera = defaults.string(forKey: "cameraID").flatMap { id in cameras.first { $0.id == id } }
            ?? CaptureDevices.defaultCamera ?? cameras.first
        let mic = defaults.string(forKey: "micID").flatMap { id in microphones.first { $0.id == id } }
            ?? CaptureDevices.defaultMicrophone ?? microphones.first
        return (camera, mic)
    }

    static func remembered(camera: CaptureDevice?, mic: CaptureDevice?) -> SyncCalibrations.Calibration? {
        guard let camera, let mic else { return nil }
        return SyncCalibrations.load().calibration(camera: camera.id, mic: mic.id)
    }

    var isRunning: Bool { progress.isRunning }

    /// The lip sync for this camera and mic, in milliseconds: 0 until it's set.
    var milliseconds: Int { saved?.milliseconds ?? 0 }

    /// Whether there's a camera and a mic to calibrate.
    var canCalibrate: Bool { camera != nil && mic != nil }

    /// The camera's picture while calibrating, so the creator can see the phone is in view.
    var preview: CameraPreviewFeed? { capture.preview }

    func start() {
        let previous = run
        previous?.cancel()
        let request = progress.begin()
        run = Task { [weak self] in
            // Cancellation doesn't interrupt a permission prompt or a device's asynchronous start.
            // Drain its cleanup before the next run touches the same capture objects.
            await previous?.value
            guard let self, !Task.isCancelled, self.progress.contains(request) else { return }
            await self.listen(request: request)
        }
    }

    /// Stops listening and turns the camera and the mic off. Keep the task until its cleanup drains.
    func cancel() {
        run?.cancel()
        if isRunning { progress.reset() }
    }

    /// Sets the lip sync for this camera and mic by hand, in milliseconds: above zero for a camera behind
    /// the mic. Zero forgets it, so recordings are saved as their timestamps say.
    func set(milliseconds: Int) {
        guard let camera, let mic else { return }
        var calibrations = SyncCalibrations.load()
        calibrations.set(milliseconds == 0 ? nil : .init(byHandMilliseconds: milliseconds), camera: camera.id, mic: mic.id)
        calibrations.save()
        saved = calibrations.calibration(camera: camera.id, mic: mic.id)
    }

    /// Saves a finished measurement for this camera and mic: the creator can't judge it, so it isn't put to them.
    private func remember(_ measurement: SyncMeasurement) {
        guard let offset = measurement.offset, let camera, let mic else { return }
        var calibrations = SyncCalibrations.load()
        calibrations.set(.init(offset: offset, measuredAt: .now, readings: measurement.agreeing.count), camera: camera.id, mic: mic.id)
        calibrations.save()
        saved = calibrations.calibration(camera: camera.id, mic: mic.id)
    }

    private func listen(request: UUID) async {
        guard let camera, let mic else {
            progress.fail("Needs a camera and a mic.", for: request)
            return
        }
        defer { capture.stop() }
        do {
            try await capture.start(camera: camera, mic: mic)
            try Task.checkCancellation()
        } catch {
            if !Task.isCancelled { progress.fail(error.localizedDescription, for: request) }
            return
        }
        let began = Date.now
        var latest = SyncMeasurement(flashes: [], beeps: [])
        progress.listening(latest, for: request)
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            latest = await capture.measurement()
            if Task.isCancelled { return }
            if latest.isComplete {
                guard progress.contains(request) else { return }
                remember(latest)
                progress.complete(latest, for: request)
                return
            }
            if capture.cameraIsUnreadable {
                progress.fail("This camera can’t be measured.", for: request)
                return
            }
            if Date.now.timeIntervalSince(began) > Self.patience {
                progress.fail("Nothing measured.", for: request)
                return
            }
            progress.listening(latest, for: request)
        }
    }
}

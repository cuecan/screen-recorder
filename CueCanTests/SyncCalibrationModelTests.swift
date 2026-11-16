import Foundation
import RecorderKit
import Testing
@testable import CueCan

@MainActor
struct SyncCalibrationModelTests {
    @Test(arguments: [false, true])
    func retryWaitsForCancelledStartupAndItsCleanup(oldStartFails: Bool) async throws {
        let capture = GatedCalibrationCapture()
        let model = SyncCalibrationModel(camera: .init(id: "test-camera", name: "Camera"),
                                         mic: .init(id: "test-mic", name: "Mic"), capture: capture)
        model.start()
        try await wait { capture.starts == 1 }
        model.cancel()
        model.start()
        // The first permission/device start ignores cancellation until its callback arrives.
        for _ in 0..<10 { await Task.yield() }
        #expect(capture.starts == 1)
        #expect(capture.stops == 0)
        if case .starting = model.stage {} else { Issue.record("The retry must wait in its starting state.") }
        capture.release(failing: oldStartFails)
        try await wait { capture.starts == 2 }
        #expect(capture.events.prefix(3).elementsEqual(["start", "stop", "start"]))
        if case .listening = model.stage {} else { Issue.record("A cancelled run must not replace the new run's status.") }
        model.cancel()
        try await wait { capture.stops == 2 }
        #expect(model.stage == .ready)
    }

    @Test func cancelledStartupCannotPublishItsLateFailure() async throws {
        let capture = GatedCalibrationCapture()
        let model = SyncCalibrationModel(camera: .init(id: "test-camera", name: "Camera"),
                                         mic: .init(id: "test-mic", name: "Mic"), capture: capture)
        model.start()
        try await wait { capture.starts == 1 }
        model.cancel()
        capture.release(failing: true)
        try await wait { capture.stops == 1 }
        #expect(model.stage == .ready)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock().now + .seconds(3)
        while !condition() {
            guard clock.now < deadline else { throw NSError(domain: "CalibrationWait", code: 1) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class GatedCalibrationCapture: SyncCalibrationCapture {
    var events: [String] = []
    var starts: Int { events.count { $0 == "start" } }
    var stops: Int { events.count { $0 == "stop" } }
    private var pending: CheckedContinuation<Void, any Error>?
    func start(camera: CaptureDevice, mic: CaptureDevice) async throws {
        events.append("start")
        if starts == 1 { try await withCheckedThrowingContinuation { pending = $0 } }
    }
    func release(failing: Bool) {
        if failing { pending?.resume(throwing: NSError(domain: "OldPermissionReply", code: 1)) }
        else { pending?.resume() }
        pending = nil
    }
    func stop() { events.append("stop") }
    func measurement() async -> SyncMeasurement { SyncMeasurement(flashes: [], beeps: []) }
    var cameraIsUnreadable: Bool { false }
}

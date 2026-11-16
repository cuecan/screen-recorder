import Foundation
import Testing
import RecorderKit

struct DeviceReadinessTests {
    let camera = CaptureDevice(id: "camera", name: "Camera")

    @Test func failedStartupCannotEnableCameraOnlyRecording() {
        var device = DeviceReadiness()
        device.requestPermission()
        #expect(device.isPreparing)
        let attempt = device.start(camera)
        device.finish(attempt, problem: "In use")
        #expect(!device.isReady)
        #expect(!device.isPreparing)
        let conditions = StartConditions(isSettingUp: true, hasFormat: true, recordsScreen: false,
                                         hasArea: false, hasCamera: device.isReady, devicesReady: !device.isPreparing)
        #expect(!conditions.canStart)
        let retry = device.start(camera)
        device.finish(retry, problem: nil)
        #expect(device.isReady)
    }

    @Test func startupCannotReviveAClosedOrReplacedDevice() {
        var device = DeviceReadiness()
        let old = device.start(camera)
        device.stop()
        #expect(!{ device.finish(old, problem: nil) }())
        let current = device.start(camera)
        #expect(!{ device.finish(old, problem: "Old failure") }())
        #expect(device.contains(current))
        device.finish(current, problem: nil)
        device.disconnected(CaptureDevice(id: "other", name: "Other"))
        #expect(device.isReady)
        device.disconnected(camera)
        #expect(!device.isReady)
    }
}

import Foundation
import Testing
@testable import RecorderKit

/// Frame monitoring tests use uptime values, independently of real camera hardware.
@Suite struct CameraFrameWatchTests {
    @Test func framesArrivingMeanTheCameraIsOn() {
        var watch = CameraFrameWatch(startedAt: 10)
        #expect(watch.check(lastFrame: nil, now: 11) == .waiting)
        #expect(!watch.hasPicture)
        #expect(watch.check(lastFrame: 11.5, now: 12) == .delivering)
        #expect(watch.hasPicture)
        #expect(watch.check(lastFrame: 11.5, now: 13.9) == .delivering)
    }

    @Test func noPictureIsStartedAgainThenGivenUp() throws {
        var watch = CameraFrameWatch(startedAt: 10)
        for time in [12.6, 15.2] {
            guard case .restart(let request) = watch.check(lastFrame: nil, now: time) else {
                Issue.record("Expected a restart at \(time)")
                return
            }
            #expect(!watch.hasPicture)
            let finished = watch.restartFinished(request, at: time)
            #expect(finished)
            #expect(watch.check(lastFrame: nil, now: time + 1) == .waiting)
        }
        #expect(watch.check(lastFrame: nil, now: 17.8) == .failed)
        #expect(watch.state == .failed)
        #expect(watch.restartCount == CameraFrameWatch.restarts)
        #expect(watch.check(lastFrame: 17.9, now: 18) == .failed, "Choosing the camera again starts a fresh watch.")
    }

    @Test func aSlowRestartGetsAFullWaitAfterItFinishes() throws {
        var watch = CameraFrameWatch(startedAt: 0)
        guard case .restart(let request) = watch.check(lastFrame: nil, now: 3) else {
            Issue.record("Expected the initial restart")
            return
        }
        #expect(watch.check(lastFrame: nil, now: 20) == .waiting, "No duplicate restart while capture is restarting.")
        #expect(watch.restartCount == 1)
        let stale = watch.restartFinished(UUID(), at: 20)
        #expect(!stale, "A stale completion cannot finish this restart.")
        let finished = watch.restartFinished(request, at: 20)
        #expect(finished)
        let duplicate = watch.restartFinished(request, at: 21)
        #expect(!duplicate, "A duplicate completion must not extend the wait.")
        #expect(watch.check(lastFrame: nil, now: 22) == .waiting)
        #expect(watch.check(lastFrame: 22.1, now: 22.2) == .delivering)
    }

    @Test func aPictureThatStopsIsStartedAgain() {
        var watch = CameraFrameWatch(startedAt: 0)
        #expect(watch.check(lastFrame: 5, now: 6) == .delivering)
        guard case .restart = watch.check(lastFrame: 5, now: 8) else {
            Issue.record("Expected a restart after frames stopped")
            return
        }
        #expect(!watch.hasPicture)
    }

    @Test func aFrameFromBeforeARestartDoesntCount() {
        var watch = CameraFrameWatch(startedAt: 0)
        guard case .restart(let request) = watch.check(lastFrame: nil, now: 3) else {
            Issue.record("Expected a restart")
            return
        }
        watch.restartFinished(request, at: 10)
        #expect(watch.check(lastFrame: 9.9, now: 10.5) == .waiting)
    }

    @Test func startWaitsForTheCamerasPicture() {
        let waiting = StartConditions(isSettingUp: true, hasFormat: true, hasArea: true, hasCamera: true, devicesReady: true, cameraHasPicture: false)
        #expect(!waiting.canStart)
        #expect(waiting.blocker == "Waiting for the camera’s picture")
        let noCamera = StartConditions(isSettingUp: true, hasFormat: true, hasArea: true, hasCamera: false, devicesReady: true, cameraHasPicture: false)
        #expect(noCamera.canStart, "No camera chosen: there's no picture to wait for.")
    }
}

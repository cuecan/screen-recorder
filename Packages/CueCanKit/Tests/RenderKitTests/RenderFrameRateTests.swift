import Foundation
import ProjectKit
import Testing
@testable import RenderKit

@Suite struct RenderFrameRateTests {
    @Test(arguments: [
        ([60, 30], 60), ([30], 30), ([24], 24), ([25], 25), ([48], 50), ([120], 60), ([10], 24), ([], 30), ([0], 30),
    ]) func choosesAStandardEditingClock(rates: [Int], expected: Int) {
        #expect(RenderFrameRate.standard(forCaptureRates: rates) == expected)
    }

    /// Real takes measured their 60 fps screen at 2.9, 31, 32.6, 42.4 and 55.6, by how busy it was. The clock
    /// must not follow that: every one of them is a 60 fps take.
    @Test(arguments: [2.9, 30.99, 32.64, 42.4, 55.59]) func aQuietScreenStillGetsItsCaptureClock(measured: Double) {
        var project = Project(title: "Clock")
        let take = project.addSource(name: "Take", origin: .recorded, tracks: [
            SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: 10, video: .init(width: 1920, height: 1080, frameRate: measured, captureRate: 60, codec: "hvc1"))),
            SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), media: MediaInfo(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 28.9, captureRate: 30, codec: "hvc1"))),
        ])
        #expect(RenderFrameRate.standard(for: project, playing: [take.id]) == 60)
    }

    @Test func aCameraAloneKeepsTheCamerasClock() {
        var project = Project(title: "Clock")
        let take = project.addSource(name: "Take", origin: .recorded, tracks: [
            SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), media: MediaInfo(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 28.4, captureRate: 30, codec: "hvc1"))),
        ])
        #expect(RenderFrameRate.standard(for: project, playing: [take.id]) == 30)
        #expect(RenderFrameRate.standard(for: project, playing: []) == 30)
    }
}

import Foundation
import Testing
import ProjectKit
@testable import RenderKit

struct OverlayCompositionReviewTests {
    @Test func overlappingScreenOverlaysKeepTheCameraAndOriginalScreenSlot() async throws {
        let fixture = try await CompositionTests()
        let folder = fixture.folder
        let portrait = folder.url.appending(path: "portrait.png")
        let landscape = folder.url.appending(path: "landscape.png")
        try SyntheticMedia.writePNG(SyntheticMedia.red, width: 20, height: 80, to: portrait)
        try SyntheticMedia.writePNG(SyntheticMedia.green, width: 64, height: 54, to: landscape)
        try folder.updateEdit(author: .system("Test"), reason: "Overlapping overlays") { edit in
            for picture in [portrait, landscape] {
                _ = try edit.placeOverlay(.file(at: picture), overTimeline: TimeRange(start: 0.2, end: 0.8), placement: .inScreensPlace)
            }
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let frames = try await FrameGrabber.stills(of: built, at: [0.5], maximumWidth: 960)
        let still = try #require(frames.first)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 40, y: 270)?.isClose(to: SyntheticMedia.green) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 600, y: 270)?.isClose(to: SyntheticMedia.green) == true)
    }
}

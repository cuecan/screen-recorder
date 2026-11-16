import CoreGraphics
import Foundation
import ProjectKit
import Testing
@testable import RecorderKit

@Suite struct RecordingPanelLayoutTests {
    @Test func thePreviewOpensAtFullsWidthsAndCameraOnlyAt220() {
        #expect(RecordingPanelLayout.firstWidth(showing: .preview, destination: .landscape) == 376, "A 356 × 200 video and the padding.")
        #expect(RecordingPanelLayout.firstWidth(showing: .preview, destination: .vertical) == 260, "A 240 × 427 Short and the padding.")
        #expect(RecordingPanelLayout.firstWidth(showing: .preview, destination: .both) == 497, "The 356 pt video, an 8 pt gap and the 113 pt Short.")
        #expect(RecordingPanelLayout.firstWidth(showing: .preview, destination: nil) == 376)
        #expect(RecordingPanelLayout.firstWidth(showing: .camera, destination: .both) == 220)
    }

    @Test func theChromeKeepsItsSizeAndTheHeightFollowsTheWidth() {
        #expect(RecordingPanelLayout.chromeHeight == 120)
        // The board's sizes (RecPanel.dc.html).
        #expect(RecordingPanelLayout.size(width: 376, showing: .preview, destination: .landscape) == CGSize(width: 376, height: 320))
        #expect(RecordingPanelLayout.size(width: 260, showing: .preview, destination: .vertical) == CGSize(width: 260, height: 547))
        #expect(RecordingPanelLayout.size(width: 497, showing: .preview, destination: .both) == CGSize(width: 497, height: 320))
        #expect(RecordingPanelLayout.size(width: 220, showing: .camera, destination: .landscape) == CGSize(width: 220, height: 320))
        #expect(RecordingPanelLayout.size(width: 440, showing: .camera, destination: .vertical) == CGSize(width: 440, height: 540))
    }

    @Test func thePreviewsTilesFillTheWidth() {
        #expect(RecordingPanelLayout.pictureSize(width: 220, showing: .preview, destination: .landscape) == CGSize(width: 200, height: 113))
        #expect(RecordingPanelLayout.pictureSize(width: 220, showing: .preview, destination: .vertical) == CGSize(width: 200, height: 356))
        #expect(RecordingPanelLayout.pictureSize(width: 220, showing: .preview, destination: .both) == CGSize(width: 200, height: 82))
        // The tiles at that height, side by side with the gap, fill the content to within a point.
        for width in [220.0, 320, 497, 700, 1200] {
            let height = RecordingPanelLayout.previewTileHeight(contentWidth: width - 20, destination: .both)
            let tiles = RecordingPanelLayout.previewTileWidth(.landscape, height: height) + RecordingPanelLayout.previewTileWidth(.vertical, height: height) + 8
            #expect(abs(tiles - (width - 20)) <= 1.5)
        }
    }

    @Test func itIsNeverNarrowerThan220() {
        #expect(RecordingPanelLayout.size(width: 150, showing: .preview, destination: .landscape).width == 220)
        #expect(RecordingPanelLayout.clampedWidth(100, showing: .camera, destination: nil, within: CGSize(width: 1512, height: 944)) == 220)
    }

    @Test func itIsNeverBiggerThanTheDisplay() {
        let laptop = CGSize(width: 1512, height: 944)
        // Vertical's height runs out first: 944 − 120 = 824 pt of Short, 464 pt wide, and the padding.
        #expect(RecordingPanelLayout.maximumWidth(showing: .preview, destination: .vertical, within: laptop) == 483)
        #expect(RecordingPanelLayout.size(width: 483, showing: .preview, destination: .vertical, ).height <= 944)
        #expect(RecordingPanelLayout.maximumWidth(showing: .camera, destination: nil, within: laptop) == 844)
        // A wide Both runs out of width first.
        #expect(RecordingPanelLayout.maximumWidth(showing: .preview, destination: .both, within: CGSize(width: 1000, height: 2000)) == 1000)
        #expect(RecordingPanelLayout.clampedWidth(5000, showing: .preview, destination: .landscape, within: laptop) == 1484, "824 pt of video, 1464 pt wide.")
    }

    @Test func theHeightGivesBackItsWidth() {
        for shows in RecordingPanelShows.allCases {
            for destination in VideoFormat.Destination.allCases {
                let size = RecordingPanelLayout.size(width: 400, showing: shows, destination: destination)
                let width = RecordingPanelLayout.width(forHeight: size.height, showing: shows, destination: destination)
                #expect(abs(width - 400) < 3, "\(shows) \(destination)")
            }
        }
    }

    @Test func below260TheWordsDrop() {
        #expect(RecordingPanelLayout.isNarrow(width: 220))
        #expect(RecordingPanelLayout.isNarrow(width: 259))
        #expect(!RecordingPanelLayout.isNarrow(width: 260), "Vertical's first width keeps its words.")
        #expect(!RecordingPanelLayout.isNarrow(width: 376))
    }
}

@Suite struct RecordingPanelResizeTests {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 944)
    /// Landscape's first panel, 376 × 320, near the top right.
    let start = CGRect(x: 1000, y: 500, width: 376, height: 320)

    @Test func theRightEdgeSetsTheWidthAndKeepsTheTopLeft() {
        let frame = RecordingPanelResize.frame(from: start, dragging: .right, by: CGVector(dx: 124, dy: 40),
                                               showing: .preview, destination: .landscape, within: display)
        #expect(frame.width == 500)
        #expect(frame.height == 390, "A 480 × 270 video.")
        #expect(frame.minX == start.minX)
        #expect(frame.maxY == start.maxY)
    }

    @Test func theLeftEdgeKeepsTheRightEdge() {
        let frame = RecordingPanelResize.frame(from: start, dragging: .left, by: CGVector(dx: 100, dy: 0),
                                               showing: .preview, destination: .landscape, within: display)
        #expect(frame.width == 276)
        #expect(frame.maxX == start.maxX)
        #expect(frame.maxY == start.maxY)
    }

    @Test func theBottomEdgeChangesTheWidthToMatch() {
        // Dragged down 90 pt: a 290 pt preview, 516 pt wide, grown around the panel's middle.
        let frame = RecordingPanelResize.frame(from: start, dragging: .bottom, by: CGVector(dx: 0, dy: -90),
                                               showing: .preview, destination: .landscape, within: display)
        #expect(frame.height == 410)
        #expect(frame.width == 536)
        #expect(frame.maxY == start.maxY)
        #expect(abs(frame.midX - start.midX) <= 1)
    }

    @Test func theTopEdgeKeepsTheBottomEdge() {
        let frame = RecordingPanelResize.frame(from: start, dragging: .top, by: CGVector(dx: 0, dy: 20),
                                               showing: .camera, destination: .landscape, within: display)
        #expect(frame.size == CGSize(width: 240, height: 340), "Dragged up 20 pt: a 220 pt camera.")
        #expect(frame.minY == start.minY)
    }

    @Test func aCornerTakesTheBiggerOfItsTwoProposals() {
        let frame = RecordingPanelResize.frame(from: start, dragging: [.bottom, .right], by: CGVector(dx: 20, dy: -200),
                                               showing: .preview, destination: .landscape, within: display)
        #expect(frame.width > start.width + 20, "The bottom edge's proposal is bigger.")
        #expect(frame.minX == start.minX)
        #expect(frame.maxY == start.maxY)
        #expect(frame.maxX <= display.maxX, "Stopped at the display's right edge rather than pushed left.")
    }

    @Test func itStopsAt220AndAtTheDisplay() {
        let small = RecordingPanelResize.frame(from: start, dragging: .left, by: CGVector(dx: 300, dy: 0),
                                               showing: .preview, destination: .both, within: display)
        #expect(small.width == 220)
        #expect(small.height == 202)
        #expect(small.maxX == start.maxX)
        let tall = RecordingPanelResize.frame(from: CGRect(x: 100, y: 397, width: 260, height: 547), dragging: .right,
                                              by: CGVector(dx: 2000, dy: 0), showing: .preview, destination: .vertical, within: display)
        #expect(display.contains(tall))
        #expect(tall.width == 483)
    }

    @Test func aProblemLineIsKeptOnTop() {
        let frame = RecordingPanelResize.frame(from: CGRect(x: 1000, y: 480, width: 376, height: 340), dragging: .right,
                                               by: CGVector(dx: 124, dy: 0), showing: .preview, destination: .landscape,
                                               extraHeight: 20, within: display)
        #expect(frame.height == 410)
    }
}

@Suite struct RecordingPanelMemoryTests {
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let teleprompter = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    @Test func theFirstTimeItShowsThePreviewAtFullsWidth() {
        let memory = RecordingPanelMemory()
        #expect(memory.shows(on: "laptop", cameraOn: true) == .preview)
        #expect(memory.width(on: "laptop", showing: .preview, destination: .both) == 497)
        #expect(memory.width(on: nil, showing: .camera, destination: .both) == 220)
    }

    @Test func itRemembersTheViewPlaceAndWidthsPerDisplay() throws {
        var memory = RecordingPanelMemory()
        memory.remember(showing: .camera, destination: .landscape, frame: CGRect(x: 1200, y: 600, width: 260, height: 360), on: "laptop", displayFrame: laptop)
        memory.remember(showing: .preview, destination: .both, frame: CGRect(x: 1600, y: 500, width: 700, height: 400), on: "teleprompter", displayFrame: teleprompter)
        #expect(memory.lastDisplay == "teleprompter")
        #expect(memory.shows(on: "laptop", cameraOn: true) == .camera)
        #expect(memory.shows(on: "teleprompter", cameraOn: true) == .preview)
        #expect(memory.width(on: "laptop", showing: .camera, destination: .vertical) == 260)
        #expect(memory.width(on: "teleprompter", showing: .preview, destination: .both) == 700)
        #expect(memory.width(on: "teleprompter", showing: .camera, destination: .both) == 220, "Never Camera only there.")
        let frame = try #require(memory.frame(on: "teleprompter", panelSize: CGSize(width: 700, height: 400), displayFrame: teleprompter, visible: teleprompter))
        #expect(frame == CGRect(x: 1600, y: 500, width: 700, height: 400))
        #expect(memory.frame(on: "elsewhere", panelSize: .zero, displayFrame: laptop, visible: laptop) == nil)
    }

    @Test func thePreviewsWidthIsKeptPerFormat() {
        var memory = RecordingPanelMemory()
        memory.remember(showing: .preview, destination: .both, frame: CGRect(x: 0, y: 0, width: 800, height: 400), on: "a", displayFrame: laptop)
        memory.remember(showing: .preview, destination: .vertical, frame: CGRect(x: 0, y: 0, width: 230, height: 500), on: "a", displayFrame: laptop)
        #expect(memory.width(on: "a", showing: .preview, destination: .both) == 800)
        #expect(memory.width(on: "a", showing: .preview, destination: .vertical) == 230)
        #expect(memory.width(on: "a", showing: .preview, destination: .landscape) == 376, "Landscape's first width.")
        #expect(memory.width(on: "a", showing: .preview, destination: nil) == 376)
    }

    @Test func cameraOnlyOpensOnThePreviewWithTheCameraOff() {
        var memory = RecordingPanelMemory()
        memory.remember(showing: .camera, destination: .landscape, frame: CGRect(x: 0, y: 0, width: 220, height: 320), on: "a", displayFrame: laptop)
        #expect(memory.shows(on: "a", cameraOn: false) == .preview)
        #expect(memory.shows(on: "a", cameraOn: true) == .camera)
    }

    @Test func aRememberedPlaceFollowsItsDisplayAndStaysOnIt() throws {
        var memory = RecordingPanelMemory()
        memory.remember(showing: .camera, destination: nil, frame: CGRect(x: 1700, y: 800, width: 220, height: 260), on: "teleprompter", displayFrame: teleprompter)
        // The teleprompter display moved to the left of the laptop.
        let moved = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = try #require(memory.frame(on: "teleprompter", panelSize: CGSize(width: 220, height: 260), displayFrame: moved, visible: moved))
        #expect(frame.origin == CGPoint(x: -1920 + 188, y: 800))
        // Bigger in the same place: it grows down from its top left, and stays on the display.
        let big = try #require(memory.frame(on: "teleprompter", panelSize: CGSize(width: 500, height: 1000), displayFrame: moved, visible: moved))
        #expect(moved.contains(big))
    }

    @Test func itRoundTripsThroughJSON() throws {
        var memory = RecordingPanelMemory(isHidden: true)
        memory.remember(showing: .preview, destination: .vertical, frame: CGRect(x: 10, y: 20, width: 300, height: 600), on: "a", displayFrame: laptop)
        memory.remember(showing: .camera, destination: .vertical, frame: CGRect(x: 10, y: 20, width: 240, height: 340), on: "a", displayFrame: laptop)
        let decoded = try JSONDecoder().decode(RecordingPanelMemory.self, from: JSONEncoder().encode(memory))
        #expect(decoded == memory)
    }
}

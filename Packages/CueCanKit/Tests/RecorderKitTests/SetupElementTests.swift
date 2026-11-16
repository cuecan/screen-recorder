import CoreGraphics
import Foundation
import ProjectKit
import Testing
@testable import RecorderKit

/// The setup element as one window (docs/decisions.md, 79; docs/ui.md, R10).
@Suite struct SetupElementTests {
    /// A 5K display's available desktop, and a 1512 × 982 laptop's with a 37 pt menu bar (VERIFY).
    let studio = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 945)

    @Test func theElementIsAsTallAsTheBoardSays() {
        #expect(SetupElementLayout.height(previewHeight: 200) == 365, "Landscape and Both")
        #expect(SetupElementLayout.height(previewHeight: 427) == 592, "Vertical")
    }

    @Test func aShortDisplayShrinksOnlyVerticalsPreview() {
        #expect(SetupElementLayout.previewHeight(for: .vertical, visibleHeight: studio.height) == 427)
        #expect(SetupElementLayout.previewHeight(for: .vertical, visibleHeight: laptop.height) == 307)
        #expect(SetupElementLayout.previewHeight(for: .vertical, visibleHeight: 1080) == 375, "A 1728 × 1117 laptop")
        for destination in [VideoFormat.Destination.landscape, .both, nil] {
            #expect(SetupElementLayout.previewHeight(for: destination, visibleHeight: laptop.height) == 200)
        }
        let element = SetupElementLayout.height(previewHeight: SetupElementLayout.previewHeight(for: .vertical, visibleHeight: laptop.height))
        #expect(element <= laptop.height / 2)
        #expect(SetupElementLayout.previewHeight(for: .vertical, visibleHeight: 300) == SetupElementLayout.minimumPreviewHeight)
    }

    @Test func theStripStaysPutAndTheWellGrowsUp() {
        let element = CGRect(x: 900, y: 16, width: 656, height: 365)
        let taller = SetupElementPlacement.resized(element, toHeight: 592, within: studio)
        #expect(taller.minY == 16)
        #expect(taller.height == 592)
        let shorter = SetupElementPlacement.resized(taller, toHeight: 365, within: studio)
        #expect(shorter == element)
    }

    @Test func withNoRoomAboveTheStripMovesDown() {
        let atTop = CGRect(x: 900, y: studio.maxY - 365, width: 656, height: 365)
        let withMenu = SetupElementPlacement.resized(atTop, toHeight: 365 + 150, within: studio)
        #expect(withMenu.maxY == studio.maxY)
        #expect(withMenu.minY == studio.maxY - 515)
    }

    @Test func theElementComesBackWhereItWasOnEachDisplay() throws {
        let display = CGRect(x: 2560, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 2560, y: 0, width: 1512, height: 945)
        var places = SetupElementPlaces()
        #expect(places.frame(on: "laptop", size: CGSize(width: 656, height: 365), displayFrame: display, visible: visible) == nil)
        places.remember(CGRect(x: 2700, y: 40, width: 656, height: 365), on: "laptop", displayFrame: display)
        let back = try #require(places.frame(on: "laptop", size: CGSize(width: 656, height: 472), displayFrame: display, visible: visible))
        #expect(back.origin == CGPoint(x: 2700, y: 40), "The strip comes back where it was, whatever the preview's height.")

        let data = try JSONEncoder().encode(places)
        #expect(try JSONDecoder().decode(SetupElementPlaces.self, from: data) == places)
    }

    @Test func itStartsAtTheBottomCentreTheFirstTime() {
        let frame = SetupElementPlacement.first(size: CGSize(width: 656, height: 365), area: nil, display: studio)
        #expect(frame.midX == studio.midX)
        #expect(frame.minY == studio.minY + ControlPlacement.margin)
    }

    @Test func theTitleBarSaysWhyItCantStartYet() {
        let noFormat = StartConditions(isSettingUp: true, hasFormat: false, hasArea: false, devicesReady: true)
        #expect(noFormat.headline == "Pick where you’ll post it")
        let waiting = StartConditions(isSettingUp: true, hasFormat: true, hasArea: true, devicesReady: true, cameraHasPicture: false)
        #expect(waiting.headline == "Waiting for the camera’s picture")
        let ready = StartConditions(isSettingUp: true, hasFormat: true, hasArea: true, devicesReady: true)
        #expect(ready.headline == nil)
    }

    @Test func theChoicesPictureFillsTheWellBesideItsSettings() {
        #expect(SetupWellLayout.choicePictureHeight(previewHeight: 200, destination: .landscape) == 148)
        #expect(SetupWellLayout.choicePictureHeight(previewHeight: 427, destination: .vertical) == 375)
        // Both's video and Short share the room beside the settings.
        #expect(SetupWellLayout.choicePictureHeight(previewHeight: 200, destination: .both) == 137)
        for destination in VideoFormat.Destination.allCases {
            let height = SetupWellLayout.choicePictureHeight(previewHeight: 427, destination: destination)
            let row = height * SetupWellLayout.widthPerHeight(destination) + SetupWellLayout.choicesGap + SetupWellLayout.choicesControlsWidth
            #expect(row <= SetupElementLayout.width - 16 - 24)
        }
    }

    @Test func aShortWellGivesASmallerPicture() {
        #expect(SetupWellLayout.choicePictureHeight(previewHeight: 307, destination: .vertical) == 307 - 52)
    }

    @Test func framingStacksWhereTheWellIsTall() {
        let vertical = SetupWellLayout.framing(previewHeight: 427, hasTabs: false)
        #expect(vertical.isStacked)
        #expect(vertical.frame == CGSize(width: 616, height: 346))
        let landscape = SetupWellLayout.framing(previewHeight: 200, hasTabs: false)
        #expect(!landscape.isStacked)
        #expect(landscape.frame == CGSize(width: 356, height: 200))
        let both = SetupWellLayout.framing(previewHeight: 200, hasTabs: true)
        #expect(!both.isStacked)
        // Side by side, the frame and its two columns fit the well.
        #expect(both.frame.width + 2 * (SetupWellLayout.framingColumn + 12) <= SetupElementLayout.width - 16 - 24)
        let capped = SetupWellLayout.framing(previewHeight: 285, hasTabs: false)
        #expect(capped.isStacked, "A capped Vertical well still stacks, for a bigger frame than side by side.")
        #expect(capped.frame.height + 34 <= 285)
    }

    @Test func theFramingCircleSaysWhyItsDimmed() {
        #expect(SetupWellLayout.framingBlocker(hasFormat: false, cameraOn: true, cameraHasPicture: true) == "Pick where you’ll post it first")
        #expect(SetupWellLayout.framingBlocker(hasFormat: true, cameraOn: false, cameraHasPicture: false) == "No camera to frame")
        #expect(SetupWellLayout.framingBlocker(hasFormat: true, cameraOn: true, cameraHasPicture: false) == "Waiting for the camera’s picture")
        #expect(SetupWellLayout.framingBlocker(hasFormat: true, cameraOn: true, cameraHasPicture: true) == nil)
    }
}

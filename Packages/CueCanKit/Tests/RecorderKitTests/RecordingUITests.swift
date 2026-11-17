import CoreGraphics
import Foundation
import Testing
import ProjectKit
@testable import RecorderKit

/// The geometry and decisions behind the recording UI (docs/ui.md, R2 to R6), without any windows.
@Suite struct AreaStickingTests {
    /// A 1512 × 982 pt laptop display, less a 24 pt menu bar.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 958)

    @Test func cornersStickAtThePresetsThatFitAndTheLargest() {
        #expect(AreaSticking.heights(for: .nineByEight, display: laptop) == [958, 810, 540])
        let big = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        #expect(AreaSticking.heights(for: .sixteenByNine, display: big) == [1414, 1080, 810, 540])
    }

    @Test func aHeightNearASticksThenMovesOn() {
        let heights = [958, 810, 540]
        #expect(AreaSticking.stuck(height: 803, to: heights) == 810)
        #expect(AreaSticking.stuck(height: 819, to: heights) == 810)
        #expect(AreaSticking.stuck(height: 825, to: heights) == 825, "Past the sticking distance, it moves on.")
        #expect(AreaSticking.stuck(height: 950, to: heights) == 958)
    }

    @Test func draggingACornerLandsOnAPreset() {
        let original = CGRect(x: 200, y: 50, width: 912, height: 800)
        // The top right corner dragged a little up and right: a few points short of 810.
        let resized = AreaSticking.resized(original, corner: .topRight, translation: CGSize(width: 4, height: 3), ratio: .nineByEight, within: laptop)
        #expect(resized.height == 810)
        #expect(resized.width == 912)
        #expect(resized.minX == original.minX && resized.minY == original.minY, "The opposite corner stays put.")
    }

    @Test func resizingKeepsTheShapeAndStaysOnTheDisplay() {
        let original = CGRect(x: 300, y: 200, width: 608, height: 540)
        for ratio in CaptureArea.Ratio.allCases {
            for corner in AreaGeometry.Corner.allCases {
                for delta in [CGSize(width: -3000, height: -3000), CGSize(width: 3000, height: 3000), CGSize(width: 37, height: 11)] {
                    let resized = AreaSticking.resized(original, corner: corner, translation: delta, ratio: ratio, within: laptop)
                    #expect(laptop.contains(resized))
                    #expect(Int(resized.height) % 2 == 0)
                    #expect(Int(resized.width) == ratio.width(forHeight: Int(resized.height)))
                }
            }
        }
    }

    @Test func edgesStickToTheDisplaysSides() {
        let area = CGRect(x: 100, y: 100, width: 912, height: 810)
        let nearLeft = AreaSticking.moved(area, by: CGSize(width: -92, height: 0), within: laptop)
        #expect(nearLeft.minX == 0, "8 pt from the left edge sticks to it.")
        let nearTop = AreaSticking.moved(area, by: CGSize(width: 0, height: 40), within: laptop)
        #expect(nearTop.maxY == laptop.maxY)
        let free = AreaSticking.moved(area, by: CGSize(width: 50, height: -30), within: laptop)
        #expect(free.origin == CGPoint(x: 150, y: 70))
        let pushed = AreaSticking.moved(area, by: CGSize(width: 2000, height: 0), within: laptop)
        #expect(pushed.maxX == laptop.maxX)
    }

    /// A display with a 31 pt menu bar: the desktop stops under it.
    private let wholeDisplay = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let underMenuBar = CGRect(x: 0, y: 0, width: 2560, height: 1409)

    @Test func aMovedAreaStopsUnderTheMenuBarAndGoesOverItWhenPulledFurther() {
        let area = CGRect(x: 100, y: 200, width: 1600, height: 900)
        func top(after pull: Double) -> Double {
            AreaSticking.moved(area, by: CGSize(width: 0, height: pull), within: underMenuBar, limit: wholeDisplay).maxY
        }
        // Doubles throughout: the expectation compares a Double with a CGFloat as unequal.
        let desktopTop = Double(underMenuBar.maxY), displayTop = Double(wholeDisplay.maxY)
        let reachesDesktopTop = desktopTop - Double(area.maxY)
        #expect(top(after: reachesDesktopTop - 6) == desktopTop, "Close below the menu bar sticks to it.")
        #expect(top(after: reachesDesktopTop + 8) == desktopTop, "A short pull past it stays put.")
        #expect(top(after: reachesDesktopTop + 15) == desktopTop + 15, "A longer pull goes over the menu bar.")
        #expect(top(after: reachesDesktopTop + 25) == displayTop, "Close to the top of the display sticks to it.")
        #expect(top(after: 5000) == displayTop, "It never leaves the display.")
        // Without a limit, the desktop is as far as it goes.
        #expect(AreaSticking.moved(area, by: CGSize(width: 0, height: 5000), within: underMenuBar).maxY == underMenuBar.maxY)
    }

    @Test func aResizedAreaStopsUnderTheMenuBarAndGrowsOverItWhenPulledFurther() throws {
        // 16:9, its bottom left corner fixed at the display's.
        let area = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        func height(after pull: Double) -> Double {
            AreaSticking.resized(area, corner: .topRight, translation: CGSize(width: 0, height: pull),
                                 ratio: .sixteenByNine, within: underMenuBar, limit: wholeDisplay).height
        }
        let onDesktop = Double(try #require(CaptureArea.largest(.sixteenByNine, fittingWidth: 2560, height: 1409)).heightPoints)
        // A pull straight up changes the height by a share of it, so ask for heights, not pulls.
        let aspect = CaptureArea.Ratio.sixteenByNine.aspect
        func pull(toHeight wanted: Double) -> Double { (wanted - area.height) * (aspect * aspect + 1) }
        #expect(height(after: pull(toHeight: onDesktop + 6)) == onDesktop, "A short pull past the menu bar stays put.")
        #expect(height(after: pull(toHeight: onDesktop + 16)) == onDesktop + 16)
        #expect(height(after: pull(toHeight: 3000)) == 1440, "The whole display is the most it grows to.")
        let kept = AreaSticking.resized(area, corner: .topRight, translation: CGSize(width: 0, height: pull(toHeight: 3000)),
                                        ratio: .sixteenByNine, within: underMenuBar)
        #expect(Double(kept.height) == onDesktop, "Without a limit, the desktop is as far as it grows.")
    }

    @Test func anAreaOverTheMenuBarLeavesWindowsTheDesktopPart() {
        let onDesktop = CGRect(x: 0, y: 0, width: 2502, height: 1408)
        #expect(!AreaGeometry.reaches(onDesktop, past: underMenuBar))
        #expect(AreaGeometry.windowFrame(in: onDesktop, desktop: underMenuBar) == onDesktop)
        #expect(AreaGeometry.reaches(wholeDisplay, past: underMenuBar))
        #expect(AreaGeometry.windowFrame(in: wholeDisplay, desktop: underMenuBar) == underMenuBar)
    }

    @Test func theSizeMenuOffersTheLargestAndPartsOfIt() throws {
        let offered = AreaChoice.offered(for: .sixteenByNine, desktop: underMenuBar, display: wholeDisplay)
        #expect(offered == [.largestWithMenuBar, .largest, .twoThirds, .half, .third])
        #expect(offered.map(\.title) == ["Largest with menu bar", "Largest", "Text 1.5×", "Text 2×", "Text 3×"])
        func height(_ choice: AreaChoice) -> Int? {
            choice.area(for: .sixteenByNine, desktop: underMenuBar, display: wholeDisplay)?.heightPoints
        }
        #expect(height(.largestWithMenuBar) == 1440)
        #expect(height(.largest) == 1408)
        // Parts of the largest area on the desktop, at even heights.
        #expect(height(.twoThirds) == 938)
        #expect(height(.half) == 704)
        #expect(height(.third) == 470)
    }

    @Test func aHiddenMenuBarLeavesItsRowOut() {
        // With the menu bar hidden the desktop reaches the top of the display, though a Dock takes the bottom.
        let aboveDock = CGRect(x: 0, y: 70, width: 2560, height: 1370)
        let offered = AreaChoice.offered(for: .sixteenByNine, desktop: aboveDock, display: wholeDisplay)
        #expect(offered == [.largest, .twoThirds, .half, .third])
    }

    @Test func aPartTooSmallToDragToIsNotOffered() {
        // A third of this desktop's largest 16:9 area is under the smallest height a corner allows.
        let small = CGRect(x: 0, y: 0, width: 1024, height: 500)
        #expect(AreaChoice.offered(for: .sixteenByNine, desktop: small, display: small) == [.largest, .twoThirds, .half])
    }

    @Test func aPickedSizeStaysAroundTheSameMiddleAndTheMenuBarOneGoesToTheTop() throws {
        let current = CGRect(x: 400, y: 300, width: 1600, height: 900)
        let half = try #require(AreaChoice.half.frame(for: .sixteenByNine, from: current, desktop: underMenuBar, display: wholeDisplay))
        #expect(half.size == CGSize(width: 1252, height: 704))
        #expect(half.midX == current.midX)
        #expect(half.midY == current.midY)
        let largest = try #require(AreaChoice.largest.frame(for: .sixteenByNine, from: current, desktop: underMenuBar, display: wholeDisplay))
        #expect(underMenuBar.contains(largest))
        let over = try #require(AreaChoice.largestWithMenuBar.frame(for: .sixteenByNine, from: current, desktop: underMenuBar, display: wholeDisplay))
        #expect(over == wholeDisplay)
        // A shape the display's width limits is the same size either way, and sits at the top with the menu bar.
        let tall = CGRect(x: 0, y: 0, width: 1512, height: 982), tallDesktop = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let top = try #require(AreaChoice.largestWithMenuBar.frame(for: .sixteenByNine, from: tallDesktop, desktop: tallDesktop, display: tall))
        #expect(top.size == CGSize(width: 1512, height: 850))
        #expect(top.maxY == tall.maxY)
    }

    @Test func theMenuTicksTheSizeTheAreaIsAt() throws {
        func ticked(_ frame: CGRect) -> AreaChoice? {
            AreaChoice.matching(frame, ratio: .sixteenByNine, desktop: underMenuBar, display: wholeDisplay)
        }
        #expect(ticked(wholeDisplay) == .largestWithMenuBar)
        #expect(ticked(CGRect(x: 28, y: 0, width: 2504, height: 1408)) == .largest)
        #expect(ticked(CGRect(x: 100, y: 100, width: 1252, height: 704)) == .half)
        #expect(ticked(CGRect(x: 100, y: 100, width: 1600, height: 900)) == nil, "A size dragged to in between ticks nothing.")
        #expect(ticked(CGRect(x: 28, y: 32, width: 2504, height: 1408)) == nil, "The largest size pulled over the menu bar is neither.")
    }

    @Test func theFramesLabelSaysHowBigTextWillLook() {
        let largest = CaptureArea(ratio: .nineByEight, heightPoints: 1415)
        #expect(AreaSize.frameLabel(for: CaptureArea(ratio: .nineByEight, heightPoints: 810), largest: largest) == "Text 1.7×")
        #expect(AreaSize.frameLabel(for: CaptureArea(ratio: .nineByEight, heightPoints: 1080), largest: CaptureArea(ratio: .nineByEight, heightPoints: 1080 * 2)) == "Text 2×",
                "Whole numbers lose their decimal.")
        #expect(AreaSize.frameLabel(for: largest, largest: largest) == nil, "At the largest size there's nothing to compare with.")
        #expect(AreaSize.frameLabel(for: CaptureArea(ratio: .nineByEight, heightPoints: 1400), largest: largest) == nil, "Under a tenth bigger rounds to the same.")
        #expect(AreaSize.frameLabel(for: largest, largest: nil) == nil)
    }

    @Test func aBiggerAreaHoldsTheWindowsMinimumSize() throws {
        let area = try #require(AreaSticking.smallestArea(.nineByEight, holding: CGSize(width: 1000, height: 500), display: laptop))
        #expect(area.widthPoints >= 1000)
        let smaller = CaptureArea(ratio: .nineByEight, heightPoints: area.heightPoints - 2)
        #expect(smaller.widthPoints < 1000, "It's the smallest that does.")
        #expect(AreaSticking.smallestArea(.nineBySixteen, holding: CGSize(width: 1400, height: 500), display: laptop) == nil)
    }
}

@Suite struct ControlPlacementTests {
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 958)
    let bar = CGSize(width: 600, height: 126)
    let small = CGSize(width: 184, height: 260)

    @Test func theBarStartsAtTheBottomCentre() {
        let frame = ControlPlacement.setupBar(size: bar, area: nil, display: laptop)
        #expect(frame.midX == laptop.midX)
        #expect(frame.minY == ControlPlacement.margin)
    }

    @Test func theBarStartsOutsideTheAreaWhenThereIsRoom() {
        let area = CGRect(x: 300, y: 300, width: 912, height: 500)
        let frame = ControlPlacement.setupBar(size: bar, area: area, display: laptop)
        #expect(!frame.intersects(area))
        #expect(frame.maxY <= area.minY)
    }

    @Test func theBarSitsOverAFullHeightArea() {
        let area = CGRect(x: 0, y: 0, width: 1076, height: 958)
        let frame = ControlPlacement.setupBar(size: bar, area: area, display: laptop)
        #expect(frame.minY == ControlPlacement.margin, "No room outside: it hides on Record anyway.")
    }

    @Test func thePanelGoesBesideTheArea() {
        let area = CGRect(x: 300, y: 74, width: 912, height: 810)
        let frame = ControlPlacement.panel(size: small, area: area, display: laptop)
        #expect(frame.minX == area.maxX + ControlPlacement.margin)
        #expect(frame.maxY == area.maxY)
        let wide = CGRect(x: 0, y: 54, width: 1512, height: 850)
        let corner = ControlPlacement.panel(size: small, area: wide, display: laptop)
        #expect(corner.maxX == laptop.maxX - ControlPlacement.margin, "No room beside a full-width area.")
    }
}

@Suite struct AreaPreviewTests {
    @Test func thePreviewStaysSmall() {
        #expect(AreaPreview.pixelSize(for: CGSize(width: 1512, height: 850)) == CGSize(width: 640, height: 360))
        #expect(AreaPreview.pixelSize(for: CGSize(width: 456, height: 810)).height == 640)
        #expect(AreaPreview.pixelSize(for: CGSize(width: 300, height: 200)) == CGSize(width: 300, height: 200))
    }
}

@Suite struct WindowDragTrackerTests {
    let area = CGRect(x: 300, y: 100, width: 912, height: 810)
    let browser = SnappableWindow(id: 7, processID: 42, appName: "Safari", title: "", frame: CGRect(x: 1300, y: 200, width: 800, height: 600))

    @Test func aWindowDraggedOntoTheAreaAndReleasedIsDropped() throws {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        #expect(tracker.sampled(pointer: CGPoint(x: 1400, y: 790), windowFrame: browser.frame) == nil, "Not moved yet.")
        let outside = browser.frame.offsetBy(dx: -50, dy: 0)
        #expect(tracker.sampled(pointer: CGPoint(x: 1350, y: 790), windowFrame: outside) == nil, "Moving, but the pointer isn't over the area.")
        let over = browser.frame.offsetBy(dx: -400, dy: 0)
        let entered = tracker.sampled(pointer: CGPoint(x: 1000, y: 790), windowFrame: over)
        #expect(entered == .entered(SnappableWindow(id: 7, processID: 42, appName: "Safari", title: "", frame: over)))
        #expect(tracker.sampled(pointer: CGPoint(x: 990, y: 790), windowFrame: over.offsetBy(dx: -10, dy: 0)) == nil, "Still over it.")
        let change = tracker.released(pointer: CGPoint(x: 990, y: 790), windowFrame: over.offsetBy(dx: -10, dy: 0))
        guard case .dropped(let window, let from) = change else {
            Issue.record("Expected a drop, got \(String(describing: change))")
            return
        }
        #expect(window.id == 7)
        #expect(from == browser.frame, "It goes back here if it can't fit.")
        #expect(!tracker.isTracking)
    }

    @Test func leavingTheAreaTurnsTheLightOff() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: browser.frame.offsetBy(dx: -400, dy: 0))
        #expect(tracker.sampled(pointer: CGPoint(x: 1400, y: 500), windowFrame: browser.frame.offsetBy(dx: 10, dy: 0)) == .left)
        #expect(tracker.released(pointer: CGPoint(x: 1400, y: 500), windowFrame: browser.frame) == nil)
    }

    @Test func releasingOutsideAfterBeingOverIsALeave() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: browser.frame.offsetBy(dx: -400, dy: 0))
        #expect(tracker.released(pointer: CGPoint(x: 1400, y: 500), windowFrame: browser.frame.offsetBy(dx: 5, dy: 0)) == .left)
    }

    @Test func resizingOrSelectingTextNeverSnaps() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        // A press that ends over the area without the window moving: text selection, or a click.
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: browser.frame) == nil)
        tracker.pressed(on: browser)
        // The left edge dragged: the window moves and changes size.
        let resized = CGRect(x: 1000, y: 200, width: 1100, height: 600)
        #expect(tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: resized) == nil)
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: resized) == nil)
    }

    @Test func aWindowThatDisappearsCannotBeDropped() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: browser.frame.offsetBy(dx: -400, dy: 0))
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: nil) == .left)
        #expect(!tracker.isTracking)
    }

    @Test func resizingAfterMovementRejectsTheWholeGesture() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        let moved = browser.frame.offsetBy(dx: -400, dy: 0)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved)
        #expect(tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved.insetBy(dx: 10, dy: 0)) == .left)
        #expect(!tracker.isTracking)
        // Restoring the size doesn't turn the same resize gesture into a drag.
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved) == nil)
    }

    @Test func aResizeCannotTurnIntoADragWhenItReturnsToItsStartingSize() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        let moved = browser.frame.offsetBy(dx: -400, dy: 0)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved.insetBy(dx: 10, dy: 0))
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved) == nil)
    }

    @Test func cancellationClearsTheHighlightAndAllowsANewPress() {
        var tracker = WindowDragTracker(area: area)
        tracker.pressed(on: browser)
        let moved = browser.frame.offsetBy(dx: -400, dy: 0)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved)
        #expect(tracker.cancel() == .left)
        #expect(tracker.cancel() == nil)
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved) == nil)
        tracker.pressed(on: browser)
        guard case .dropped = tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: moved) else {
            Issue.record("A fresh press should be able to drag again")
            return
        }
    }

    @Test func withNoAreaNothingIsDropped() {
        var tracker = WindowDragTracker(area: nil)
        tracker.pressed(on: browser)
        _ = tracker.sampled(pointer: CGPoint(x: 1000, y: 500), windowFrame: browser.frame.offsetBy(dx: -400, dy: 0))
        #expect(tracker.released(pointer: CGPoint(x: 1000, y: 500), windowFrame: browser.frame.offsetBy(dx: -400, dy: 0)) == nil)
    }
}

@Suite struct DiscardedTakeTests {
    private func temporaryLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "CueCanDiscard-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func aDiscardedTakeIsDeletedOutright() throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ProjectFolder.create(at: root.appending(path: "2026-11-07 Screen recording", directoryHint: .isDirectory), title: "Screen recording")
        // A session with no devices still makes its take folder, as a real one does when it starts.
        let session = try RecordingSession(project: folder, sources: .init())
        session.start()
        #expect(FileManager.default.fileExists(atPath: session.takeFolder.path(percentEncoded: false)))
        session.discard()
        try DiscardedTake.delete(folder, in: root)
        #expect(!FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.path(percentEncoded: false)), "Only the take's project goes.")
    }

    @Test func aProjectOutsideTheProjectsFolderIsNeverDeleted() throws {
        let root = try temporaryLibrary()
        let elsewhere = try temporaryLibrary()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere)
        }
        let folder = try ProjectFolder.create(at: elsewhere.appending(path: "Mine", directoryHint: .isDirectory), title: "Mine")
        #expect(throws: DiscardedTake.Refusal.notInProjectsFolder(folder.url)) { try DiscardedTake.delete(folder, in: root) }
        #expect(FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)))
    }

    @Test func aProjectWithOtherRecordingsIsNeverDeleted() throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ProjectFolder.create(at: root.appending(path: "Kept", directoryHint: .isDirectory), title: "Kept")
        _ = try folder.updateProject { project in
            _ = project.addSource(name: "Earlier take", origin: .recorded, tracks: [])
        }
        #expect(throws: DiscardedTake.Refusal.projectHasSources(folder.url)) { try DiscardedTake.delete(folder, in: root) }
        #expect(FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)))
    }
}

@Suite struct CornerDragFollowsThePointerTests {
    @Test func aCornerEndsUnderThePointer() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 2560)
        let resized = AreaSticking.resized(display, corner: .bottomRight, translation: CGSize(width: -522, height: 939), ratio: .nineBySixteen, within: display)
        #expect(abs(resized.height - 1620) < 30)
        #expect(resized.maxY == display.maxY, "The top edge stays put.")
    }
}

@Suite struct StartConditionsTests {
    @Test func startWaitsForTheCameraAndMic() {
        let waiting = StartConditions(isSettingUp: true, hasFormat: true, hasArea: true, devicesReady: false)
        #expect(!waiting.canStart, "A take started now would record without them.")
        #expect(waiting.blocker == "Getting the camera and mic ready")
        let ready = StartConditions(isSettingUp: true, hasFormat: true, hasArea: true, devicesReady: true)
        #expect(ready.canStart)
        #expect(ready.blocker == nil)
    }

    @Test func aFormatComesFirst() {
        let none = StartConditions(isSettingUp: true, hasFormat: false, hasArea: false, devicesReady: false)
        #expect(none.blocker == "Pick where you’ll post it first")
        #expect(!StartConditions(isSettingUp: false, hasFormat: true, hasArea: true, devicesReady: true).canStart)
    }

    @Test func noScreenNeedsNoAreaButNeedsTheCamera() {
        let cameraOnly = StartConditions(isSettingUp: true, hasFormat: true, recordsScreen: false, hasArea: false, hasCamera: true, devicesReady: true)
        #expect(cameraOnly.canStart, "With no screen there's no area to place.")
        let nothing = StartConditions(isSettingUp: true, hasFormat: true, recordsScreen: false, hasArea: false, hasCamera: false, devicesReady: true)
        #expect(nothing.blocker == "With no screen, pick a camera to record")
        let noFormat = StartConditions(isSettingUp: true, hasFormat: false, recordsScreen: false, hasArea: false, hasCamera: true, devicesReady: true)
        #expect(noFormat.blocker == "Pick where you’ll post it first", "The format still decides the outputs.")
        let screen = StartConditions(isSettingUp: true, hasFormat: true, recordsScreen: true, hasArea: true, hasCamera: false, devicesReady: true)
        #expect(screen.canStart, "A screen recording can go without a camera.")
    }
}

@Suite struct PreviewReconcilerTests {
    let laptop = PreviewTarget(displayID: 1, sourceRect: CGRect(x: 0, y: 0, width: 912, height: 810))

    @Test func aFailedUpdateIsRetried() {
        var reconciler = PreviewReconciler()
        #expect(reconciler.step(toward: laptop) == .start(laptop))
        reconciler.didApply(laptop)
        #expect(reconciler.step(toward: laptop) == .none)
        let moved = PreviewTarget(displayID: 1, sourceRect: laptop.sourceRect.offsetBy(dx: 40, dy: 0))
        #expect(reconciler.step(toward: moved) == .update(moved))
        // The update failed, so nothing is recorded as applied: the same request tries again.
        #expect(reconciler.step(toward: moved) == .update(moved))
        reconciler.didApply(moved)
        #expect(reconciler.applied == moved)
        #expect(reconciler.step(toward: moved) == .none)
    }

    @Test func anotherDisplayStartsAgainAndNothingWantedStops() {
        var reconciler = PreviewReconciler()
        reconciler.didApply(laptop)
        let other = PreviewTarget(displayID: 2, sourceRect: laptop.sourceRect)
        #expect(reconciler.step(toward: other) == .start(other))
        #expect(reconciler.step(toward: nil) == .stop)
        reconciler.didApply(nil)
        #expect(reconciler.step(toward: nil) == .none)
    }
}

import CoreGraphics
import Foundation
import Testing
import ProjectKit
@testable import RecorderKit

@Suite struct AreaTests {
    @Test func aSnapMustReachThePositionAsWellAsTheSize() {
        let area = CGRect(x: 300, y: 100, width: 912, height: 810)
        #expect(WindowFit.fit(result: area, area: area) == .fits)
        #expect(WindowFit.fit(result: area.offsetBy(dx: 30, dy: 0), area: area) == nil)
        #expect(WindowFit.fit(result: area.offsetBy(dx: 0.5, dy: -0.5), area: area) == .fits)
        let constrained = CGRect(x: 1300, y: 200, width: 1100, height: 810)
        #expect(WindowFit.fit(result: constrained, area: area) == .tooNarrow(minimumWidth: 1100))
    }

    /// A 1512 × 982 pt laptop display (docs/design.md, "Capture areas"), as the main display.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func sizesThatDontFitTheDisplayAreGreyedOut() {
        let options = AreaSize.options(for: .nineByEight, displayWidth: laptop.width, displayHeight: laptop.height)
        #expect(options.map(\.area.heightPoints) == [982, 810, 540, 1080])
        #expect(options.map(\.fits) == [true, true, true, false], "1080 pt doesn't fit a laptop display.")
        #expect(options[1].area.widthPoints == 912)
        #expect(AreaSize.defaultOption(for: .nineByEight, displayWidth: laptop.width, displayHeight: laptop.height)?.area.heightPoints == 982)
    }

    @Test func landscapeWithASmallCameraOffersTheLargest16By9First() throws {
        let options = AreaSize.options(for: .sixteenByNine, displayWidth: laptop.width, displayHeight: laptop.height)
        let largest = try #require(options.first)
        #expect(largest.area.widthPoints == 1512, "The display's full width on a 16:10 laptop.")
        #expect(largest.fits)
    }

    @Test func everyFormatOffersItsMaximumWithoutDuplicates() throws {
        for ratio in CaptureArea.Ratio.allCases {
            let options = AreaSize.options(for: ratio, displayWidth: 1920, displayHeight: 1080)
            let largest = try #require(CaptureArea.largest(ratio, fittingWidth: 1920, height: 1080))
            #expect(options.first?.area == largest)
            #expect(Set(options.map(\.id)).count == options.count)
        }
    }

    @Test func resizingKeepsOppositeCornerAndFitsDisplay() {
        let original = CGRect(x: 300, y: 200, width: 608, height: 540)
        for corner in AreaGeometry.Corner.allCases {
            for delta in [CGSize(width: -2000, height: -2000), CGSize(width: 2000, height: 2000), CGSize(width: 75, height: 40)] {
                let resized = AreaSticking.resized(original, corner: corner, translation: delta, ratio: .nineByEight, within: laptop)
                #expect(laptop.contains(resized))
                #expect(resized.height >= 180)
                #expect(Int(resized.width) == CaptureArea.Ratio.nineByEight.width(forHeight: Int(resized.height)))
                #expect(corner.isLeft ? resized.maxX == original.maxX : resized.minX == original.minX)
                #expect(corner.isBottom ? resized.maxY == original.maxY : resized.minY == original.minY)
            }
        }
    }

    @Test func displayChangesPreserveShapeAndCaptureBounds() throws {
        let old = CGRect(x: 1500, y: 100, width: 1216, height: 1080)
        let newDisplay = CGRect(x: -1512, y: 982, width: 1512, height: 982)
        for ratio in CaptureArea.Ratio.allCases {
            let fitted = try #require(AreaGeometry.refitted(old, ratio: ratio, to: newDisplay))
            #expect(newDisplay.contains(fitted))
            #expect(abs(fitted.width - Double(ratio.width(forHeight: Int(fitted.height)))) < 0.001)
            #expect(fitted.height <= old.height)
            let crop = AreaGeometry.sourceRect(for: fitted, onDisplay: newDisplay)
            #expect(crop.minX >= 0 && crop.minY >= 0)
            #expect(crop.maxX <= newDisplay.width && crop.maxY <= newDisplay.height)
        }
    }

    @Test func sourceRectIsFromTheDisplaysTopLeft() {
        // A second display above the main one.
        let display = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        let area = CGRect(x: 100, y: 1200, width: 912, height: 810)
        #expect(AreaGeometry.sourceRect(for: area, onDisplay: display) == CGRect(x: 100, y: 52, width: 912, height: 810))
    }

    @Test func anAreaIsKeptOnItsDisplay() {
        let moved = AreaGeometry.clamped(CGRect(x: 1400, y: -50, width: 912, height: 810), to: laptop)
        #expect(moved == CGRect(x: 600, y: 0, width: 912, height: 810))
        let dimming = AreaGeometry.dimming(around: moved, on: laptop)
        #expect(dimming.reduce(0) { $0 + $1.width * $1.height } == laptop.width * laptop.height - 912 * 810)
    }

    @Test func aWindowDraggedOutOfTheAreaIsNoLongerInIt() {
        let area = CGRect(x: 2665, y: 1661, width: 1198, height: 898)
        #expect(WindowFit.isMostlyInside(area, area: area))
        #expect(WindowFit.isMostlyInside(area.offsetBy(dx: 300, dy: -100), area: area), "Nudged, it's still in.")
        #expect(!WindowFit.isMostlyInside(area.offsetBy(dx: 700, dy: 0), area: area))
        // The same size on another display, as a window dragged there is.
        #expect(!WindowFit.isMostlyInside(CGRect(x: 86, y: 899, width: 1198, height: 898), area: area))
        #expect(!WindowFit.isMostlyInside(.zero, area: area))
    }

    @Test func windowsSayWhetherTheyFit() {
        let area = CGRect(x: 100, y: 100, width: 912, height: 810)
        #expect(WindowFit.fills(area, area: area))
        #expect(!WindowFit.fills(area.offsetBy(dx: 30, dy: 0), area: area))
        #expect(WindowFit.fit(result: CGSize(width: 912.4, height: 810), area: area.size) == .fits)
        let tooWide = WindowFit.fit(result: CGSize(width: 1100, height: 810), area: area.size)
        #expect(tooWide == .tooNarrow(minimumWidth: 1100))
        #expect(tooWide.notice(appName: "Figma") == "Figma was unable to shrink to fit, so part of it is outside the recording.")
        let tooTall = WindowFit.fit(result: CGSize(width: 912, height: 900), area: area.size)
        #expect(tooTall.notice(appName: "Xcode") == "Xcode was unable to shrink to fit, so part of it is outside the recording.")
        #expect(WindowFit.fits.notice(appName: "Safari") == nil)
        // System Settings has a fixed width: it can't grow to fill a wider area.
        let tooSlim = WindowFit.fit(result: CGSize(width: 740, height: 900), area: CGSize(width: 1066, height: 900))
        #expect(tooSlim == .tooSlim(maximumWidth: 740))
        #expect(tooSlim.notice(appName: "System Settings") == "System Settings was unable to grow to fill this area.")
        #expect(WindowFit.fit(result: CGSize(width: 1066, height: 600), area: CGSize(width: 1066, height: 900)) == .tooLow(maximumHeight: 600))
    }

    @Test func theLayoutSetsTheShape() {
        #expect(VideoFormat(destination: .both).layout == .sideBySide(.nineByEight), "Both starts with Side by side.")
        #expect(VideoFormat(destination: .both).captureRatio == .nineByEight)
        #expect(VideoFormat(destination: .both).outputs == [.landscape, .vertical])
        for destination in VideoFormat.Destination.allCases {
            for shape in TakeLayout.shares(for: destination) {
                #expect(VideoFormat(destination: destination, layout: .sideBySide(shape)).captureRatio == shape)
            }
        }
        #expect(VideoFormat(destination: .landscape, layout: .card(Card(size: .large))).captureRatio == .sixteenByNine)
        #expect(VideoFormat(destination: .landscape, layout: .sideBySide(.fourByThree)).label == "16:9 · Side by side ¼")
        #expect(VideoFormat(destination: .both).outputTitle == "16:9 video and 9:16 Short")
    }
}

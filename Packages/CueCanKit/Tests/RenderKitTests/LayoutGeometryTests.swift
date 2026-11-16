import CoreGraphics
import Foundation
import ProjectKit
import Testing
@testable import RenderKit

/// The rectangles of each layout (docs/decisions.md, 89), checked against the mockups' generator
/// (docs/ui/mockups/LayoutsTwoKinds.html), at 1080p.
struct LayoutGeometryTests {
    private let video = CGSize(width: 1920, height: 1080)
    private let short = CGSize(width: 1080, height: 1920)

    private func look(_ inset: OutputLook.Inset = .medium, side: OutputLook.CameraSide = .standard) -> OutputLook {
        OutputLook(inset: inset, cameraSide: side)
    }

    private func boxes(_ kind: LayoutGeometry.Kind, in output: OutputShape = .landscape, screen: Double = 16.0 / 9,
                       inset: OutputLook.Inset = .medium, side: OutputLook.CameraSide = .standard) -> (screen: CGRect?, camera: LayoutGeometry.Box?) {
        let all = LayoutGeometry.boxes(kind, in: output, size: output == .landscape ? video : short, screen: screen, look: look(inset, side: side))
        return (all.first { $0.role == .screen }?.rect, all.first { $0.role == .camera })
    }

    // MARK: - Side by side

    @Test func sideBySideGivesTheCameraWhatTheScreenLeaves() {
        // Inset M: a 60 px gutter around and between the tiles.
        let quarter = boxes(.sideBySide, screen: 4.0 / 3)
        #expect(quarter.screen == CGRect(x: 60, y: 60, width: 1280, height: 960))
        #expect(quarter.camera?.rect == CGRect(x: 1400, y: 60, width: 460, height: 960))
        let third = boxes(.sideBySide, screen: 32.0 / 27)
        #expect(third.screen == CGRect(x: 60, y: 60, width: 1138, height: 960))
        #expect(third.camera?.rect == CGRect(x: 1258, y: 60, width: 602, height: 960))
        let half = boxes(.sideBySide, screen: 8.0 / 9)
        #expect(half.screen == CGRect(x: 60, y: 60, width: 853, height: 960))
        #expect(half.camera?.rect == CGRect(x: 973, y: 60, width: 887, height: 960))
        #expect(third.camera?.slot == .split)
    }

    @Test func withNoInsetTheTilesTouchAndTheShareIsExact() {
        let third = boxes(.sideBySide, screen: 32.0 / 27, inset: .none)
        #expect(third.screen == CGRect(x: 0, y: 0, width: 1280, height: 1080))
        #expect(third.camera?.rect == CGRect(x: 1280, y: 0, width: 640, height: 1080))
        #expect(third.camera?.corners == .square)
    }

    @Test func aShortStacksTheCameraAboveTheScreen() {
        let third = boxes(.sideBySide, in: .vertical, screen: 27.0 / 32)
        #expect(third.camera?.rect == CGRect(x: 60, y: 60, width: 960, height: 602))
        #expect(third.screen == CGRect(x: 60, y: 722, width: 960, height: 1138))
        let flipped = boxes(.sideBySide, in: .vertical, screen: 27.0 / 32, side: .flipped)
        #expect(flipped.screen?.minY == 60 && flipped.camera?.rect.maxY == 1860)
    }

    @Test func flippingTheSidePutsTheCameraOnTheLeft() {
        let flipped = boxes(.sideBySide, screen: 4.0 / 3, side: .flipped)
        #expect(flipped.camera?.rect == CGRect(x: 60, y: 60, width: 460, height: 960))
        #expect(flipped.screen == CGRect(x: 580, y: 60, width: 1280, height: 960))
    }

    @Test func oneRecordingForBothFillsTheVideosHeightAndTheShortsWidth() {
        let wideVideo = boxes(.sideBySide, screen: 9.0 / 8, inset: .none)
        #expect(wideVideo.screen?.width == 1215 && wideVideo.camera?.rect.width == 705)
        let wideShort = boxes(.sideBySide, in: .vertical, screen: 9.0 / 8, inset: .none)
        #expect(wideShort.screen?.height == 960 && wideShort.camera?.rect.height == 960)
    }

    // MARK: - The camera and the screen alone

    @Test func theCameraAloneAlwaysFillsTheFrameWhateverTheInset() {
        for inset in OutputLook.Inset.allCases {
            let alone = boxes(.camera, inset: inset)
            #expect(alone.camera?.rect == CGRect(origin: .zero, size: video))
            #expect(alone.camera?.corners == .square)
            #expect(alone.camera?.slot == .fullScreen)
        }
    }

    @Test func theScreenAloneIsFramedByTheInset() {
        #expect(boxes(.screen, inset: .none).screen == CGRect(origin: .zero, size: video))
        #expect(boxes(.screen).screen == CGRect(x: 107, y: 60, width: 1706, height: 960))
    }

    // MARK: - A card

    @Test func twoThirdsOfTheCardIsOverASmallerScreenAndAThirdHangsOff() throws {
        let made = boxes(.card(.standard))
        let card = try #require(made.camera), screen = try #require(made.screen)
        // Medium and tall: 432 × 576, against the right margin, centred.
        #expect(card.rect == CGRect(x: 1428, y: 252, width: 432, height: 576))
        // Two-thirds of its 432 px is over the screen.
        #expect(screen.maxX == card.rect.minX + 288)
        #expect(screen.minX == 60)
        #expect(abs(screen.width / screen.height - 16.0 / 9) < 0.01)
        #expect(abs(screen.midY - 540) <= 1)
        #expect(card.slot == .card)
        // A left card mirrors it.
        let left = boxes(.card(Card(position: .left)))
        #expect(left.screen?.minX == (left.camera?.rect.maxX ?? 0) - 288 && left.screen?.maxX == 1860)
    }

    @Test func aCardAtTheTopOrBottomSplitsTheScreensTopOrBottomEdge() throws {
        let made = boxes(.card(Card(position: .bottom, shape: .wide)))
        let card = try #require(made.camera), screen = try #require(made.screen)
        #expect(card.rect == CGRect(x: 672, y: 696, width: 576, height: 324))
        #expect(screen.maxY == card.rect.minY + 216 && screen.minY == 60)
        #expect(abs(screen.midX - 960) <= 1)
        let top = boxes(.card(Card(position: .top, shape: .wide)))
        #expect(top.screen?.minY == (top.camera?.rect.maxY ?? 0) - 216 && top.screen?.maxY == 1020)
    }

    @Test func aCornerSplitsTheSideEdgeAndTheCentreIsTheSameAsFull() throws {
        let corner = boxes(.card(Card(position: .bottomRight)))
        #expect(corner.screen?.maxX == (corner.camera?.rect.minX ?? 0) + 288)
        // And the screen goes to the opposite corner, not the middle.
        #expect(corner.screen?.minX == 60 && corner.screen?.minY == 60)
        let topLeft = boxes(.card(Card(position: .topLeft)))
        #expect(topLeft.screen?.maxX == 1860 && topLeft.screen?.maxY == 1020)
        let centre = boxes(.card(Card(position: .center)))
        #expect(centre.screen == CGRect(origin: .zero, size: video))
    }

    @Test func aFullScreenFillsTheFrameAndTheInsetOnlySetsTheCardsMargin() {
        let bubble = Card.bubble
        // No inset: the card sits flush in the corner, square wherever it meets the frame.
        let none = boxes(.card(bubble), inset: .none)
        #expect(none.screen == CGRect(origin: .zero, size: video))
        #expect(none.camera?.rect == CGRect(x: 1596, y: 756, width: 324, height: 324))
        #expect(none.camera?.corners.bottomRight == 0 && none.camera?.corners.topRight == 0 && none.camera?.corners.bottomLeft == 0)
        // A square card's roundness is the bubble's, 30% of its side, on the corner inside the frame.
        #expect(abs((none.camera?.corners.topLeft ?? 0) - 97.2) < 0.01)
        let large = boxes(.card(bubble), inset: .large)
        #expect(large.screen == CGRect(origin: .zero, size: video))
        #expect(large.camera?.rect == CGRect(x: 1506, y: 666, width: 324, height: 324))
        #expect(abs((large.camera?.corners.bottomRight ?? 0) - 97.2) < 0.01)
    }

    @Test func aBiggerInsetOnlyWidensASmallerScreensMargin() {
        let none = boxes(.card(.standard), inset: .none), medium = boxes(.card(.standard)), large = boxes(.card(.standard), inset: .large)
        // With none, the screen and the card sit flush against the frame.
        #expect(none.screen?.minX == 0 && none.camera?.rect.maxX == 1920)
        #expect((none.screen?.width ?? 0) > (medium.screen?.width ?? 0) && (medium.screen?.width ?? 0) > (large.screen?.width ?? 0))
    }

    @Test func aCornerIsSquareWhereverItMeetsTheFramesEdge() throws {
        let flush = boxes(.card(.standard), inset: .none)
        let card = try #require(flush.camera)
        #expect(card.corners.topRight == 0 && card.corners.bottomRight == 0)
        #expect(card.corners.topLeft > 0 && card.corners.bottomLeft > 0)
        let all = LayoutGeometry.boxes(.card(.standard), in: .landscape, size: video, screen: 16.0 / 9, look: look(.none))
        let screen = try #require(all.first { $0.role == .screen })
        #expect(screen.corners.topLeft == 0 && screen.corners.bottomLeft == 0 && screen.corners.topRight > 0)
    }

    @Test func theSizesAndShapesAreFractionsOfTheShortSide() {
        func size(_ size: Card.Size, _ shape: Card.Shape) -> CGSize? { boxes(.card(Card(position: .center, size: size, shape: shape))).camera?.rect.size }
        #expect(size(.small, .square) == CGSize(width: 324, height: 324))
        #expect(size(.medium, .tall) == CGSize(width: 432, height: 576))
        #expect(size(.large, .tall) == CGSize(width: 540, height: 720))
        #expect(size(.medium, .wide) == CGSize(width: 576, height: 324))
    }

    @Test func aTakeRecordedNarrowerSitsAgainstTheSideAwayFromTheCard() {
        // A Side by side take shown as a card: the screen keeps the full height, hard left, and the card is over
        // the space it leaves.
        let full = boxes(.card(Card(screen: .full)), screen: 4.0 / 3, inset: .none)
        #expect(full.screen == CGRect(x: 0, y: 0, width: 1440, height: 1080))
        let left = boxes(.card(Card(position: .left, screen: .full)), screen: 4.0 / 3, inset: .none)
        #expect(left.screen == CGRect(x: 480, y: 0, width: 1440, height: 1080))
    }

    // MARK: - A Short's card

    @Test func aShortsScreenIsAlwaysFullUnderACard() {
        let made = boxes(.card(Card(position: .bottom, shape: .wide, screen: .smaller)), in: .vertical, screen: 9.0 / 16)
        #expect(made.screen == CGRect(origin: .zero, size: short))
    }

    @Test func aShortsWideCardIsSizedByTheFramesWidthAndLargeRunsEdgeToEdgeInsideTheMargin() {
        func wide(_ size: Card.Size, _ inset: OutputLook.Inset) -> CGRect? {
            boxes(.card(Card(position: .bottom, size: size, shape: .wide, screen: .full)), in: .vertical, screen: 9.0 / 16, inset: inset).camera?.rect
        }
        #expect(wide(.small, .medium)?.width == 594)
        #expect(wide(.medium, .medium)?.width == 810)
        #expect(wide(.large, .medium) == CGRect(x: 60, y: 1320, width: 960, height: 540))
        #expect(wide(.large, .none)?.width == 1080)
    }

    // MARK: - What the area shades

    @Test func theAreaShadesWhatTheCardCovers() throws {
        // Smaller: two-thirds of the card is over the screen.
        let smaller = try #require(LayoutGeometry.cover(.card(.standard), shape: .sixteenByNine, in: .landscape, look: look()))
        #expect(abs(smaller.rect.width - 288.0 / 1656) < 0.001)
        #expect(abs(smaller.rect.maxX - 1) < 0.001)
        // Full: all of it.
        let full = try #require(LayoutGeometry.cover(.card(.bubble), shape: .sixteenByNine, in: .landscape, look: look()))
        #expect(abs(full.rect.width - 324.0 / 1920) < 0.001 && abs(full.rect.height - 324.0 / 1080) < 0.001)
        // Side by side covers nothing.
        #expect(LayoutGeometry.cover(.sideBySide(.fourByThree), shape: .fourByThree, in: .landscape, look: look()) == nil)
    }

    // MARK: - Choosing a layout

    @Test func automaticIsTheLayoutTheTakeWasSetUpWith() {
        let size = CGSize(width: 3840, height: 2160), camera = CGSize(width: 1920, height: 1080)
        let card = ClipPictures(screen: size, camera: camera, recordedLayout: .card(.bubble))
        #expect(LayoutGeometry.resolved(.automatic, pictures: card) == .card(.bubble))
        let split = ClipPictures(screen: CGSize(width: 2880, height: 2160), camera: camera, recordedLayout: .sideBySide(.fourByThree))
        #expect(LayoutGeometry.resolved(.automatic, pictures: split) == .sideBySide)
        #expect(LayoutGeometry.resolved(.automatic, pictures: ClipPictures(camera: camera)) == .camera)
        #expect(LayoutGeometry.resolved(.card(.standard), pictures: ClipPictures(screen: size)) == .screen)
    }

    @Test func sideBySideOnATakeWithNoRoomShowsItsCard() {
        let whole = ClipPictures(screen: CGSize(width: 3840, height: 2160), camera: CGSize(width: 1920, height: 1080), recordedLayout: .card(.bubble))
        #expect(LayoutGeometry.resolved(.sideBySide, in: .landscape, pictures: whole) == .card(.bubble))
        let narrow = ClipPictures(screen: CGSize(width: 2880, height: 2160), camera: CGSize(width: 1920, height: 1080))
        #expect(LayoutGeometry.resolved(.sideBySide, in: .landscape, pictures: narrow) == .sideBySide)
        #expect(LayoutGeometry.resolved(.automatic, in: .landscape, pictures: narrow) == .sideBySide)
    }

    @Test func aFramePlacesTheCameraInItsSlotWithAHairlineExceptAlone() {
        let pictures = ClipPictures(screen: CGSize(width: 3840, height: 2160), camera: CGSize(width: 1920, height: 1080))
        let card = LayoutGeometry.frame(for: .card(.standard), in: .landscape, pictures: pictures)
        #expect(card.placement(.camera)?.cameraSlot == .card)
        #expect((card.placement(.camera)?.borderWidth ?? 0) > 0)
        let alone = LayoutGeometry.frame(for: .camera, in: .landscape, pictures: pictures, look: look(.large))
        #expect(alone.placement(.camera)?.frame == CGRect(origin: .zero, size: video))
        #expect(alone.placement(.camera)?.borderWidth == 0)
    }
}

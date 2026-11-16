import CoreGraphics
import Testing
import ProjectKit
@testable import RenderKit

/// Tiles have continuous corners, as macOS 26 and 27 draw them, not quarter circles.
@Suite struct TileShapeTests {
    let rect = CGRect(x: 0, y: 0, width: 400, height: 300)

    func tile(radius: Double) -> Placement {
        Placement(role: .screen, crop: CGRect(x: 0, y: 0, width: 1, height: 1), frame: rect, corners: Corners(all: radius))
    }

    @Test func aContinuousCornerEasesInAlongTheEdge() {
        let path = TileShape.path(for: tile(radius: 40), in: rect)
        let circular = CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil)
        // A quarter circle of radius 40 meets the top edge 40 pt from the corner; a continuous corner is still
        // curving there, and only meets the edge about 1.5 radii along (measured with SwiftUI: about 60 pt).
        for point in [CGPoint(x: 35, y: 0.6), CGPoint(x: 40, y: 0.2), CGPoint(x: 45, y: 0.1)] {
            #expect(circular.contains(point), "\(point) is inside a quarter-circle corner…")
            #expect(!path.contains(point), "…and outside a continuous one.")
        }
        #expect(path.contains(CGPoint(x: 200, y: 0.5)), "The edge's middle is straight and full.")
        #expect(!path.contains(CGPoint(x: 2, y: 2)), "The very corner is cut.")
    }

    @Test func eachCornerHasItsOwnRadiusAndNoneIsARectangle() {
        // A card's screen in the Short at no inset: square at the top, rounded at the bottom.
        let path = TileShape.path(corners: Corners(topLeft: 0, topRight: 0, bottomRight: 40, bottomLeft: 40), in: rect)
        #expect(path.contains(CGPoint(x: 0.5, y: 0.5)), "The top left is square.")
        #expect(!path.contains(CGPoint(x: 2, y: 298)), "The bottom left is cut.")
        #expect(TileShape.path(for: tile(radius: 0), in: rect).contains(CGPoint(x: 0.5, y: 0.5)))
    }

    @Test func theMaskIsTheRightWayUp() throws {
        // Core Graphics bitmaps go up from the bottom: a tile rounded only at its top must come out rounded at
        // the top of the image.
        let tile = Placement(role: .screen, crop: .zero, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                             corners: Corners(topLeft: 40, topRight: 40, bottomRight: 0, bottomLeft: 0))
        let mask = try #require(TileShape.mask(for: tile, size: tile.frame.size))
        let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 100, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.draw(mask, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        // Row 0 of the context's memory is the image's top row.
        #expect(bytes[0 * 100 + 1] < 30, "The top left corner is cut.")
        #expect(bytes[99 * 100 + 1] > 200, "The bottom left corner is square.")
    }

    @Test func theMaskIsTheTilesSize() throws {
        let mask = try #require(TileShape.mask(for: tile(radius: 30), size: rect.size))
        #expect(mask.width == 400 && mask.height == 300)
    }
}

/// The camera's edge, an adaptive hairline: every camera beside or over the screen has it (docs/decisions.md,
/// 61 and 66).
@Suite struct CameraBorderTests {
    let pictures = ClipPictures(screen: CGSize(width: 1215, height: 1080), camera: CGSize(width: 1920, height: 1080),
                                recordedLayout: .sideBySide(.nineByEight))

    @Test func everyCameraBesideOrOverTheScreenGetsTheHairline() throws {
        let video = LayoutGeometry.frame(for: .automatic, in: .landscape, pictures: pictures)
        let short = LayoutGeometry.frame(for: .automatic, in: .vertical, pictures: pictures, look: OutputLook(inset: .none))
        let fourK = LayoutGeometry.frame(for: .automatic, in: .landscape, pictures: pictures, scale: 2)
        let bubble = LayoutGeometry.frame(for: .card(.bubble), in: .landscape, pictures: pictures)
        let alone = LayoutGeometry.frame(for: .camera, in: .landscape, pictures: pictures)
        #expect(bubble.placement(.camera)?.borderWidth == 1, "A hairline: one pixel at 1080p.")
        #expect(video.placement(.camera)?.borderWidth == 1)
        #expect(short.placement(.camera)?.borderWidth == 1)
        #expect(fourK.placement(.camera)?.borderWidth == 2, "Two at 4K, so it looks the same.")
        #expect(video.placement(.screen)?.borderWidth == 0, "Only the camera has one.")
        #expect(alone.placement(.camera)?.borderWidth == 0, "The camera alone has nothing to set it apart from.")
    }

    @Test func theHairlineIsDarkOnLightAndLightOnDark() {
        let onWhite = TileShape.hairline(on: (1, 1, 1))
        let onGrey = TileShape.hairline(on: (0.85, 0.85, 0.85))
        let onBlack = TileShape.hairline(on: (0, 0, 0))
        #expect(onWhite.gray == 0 && onGrey.gray == 0)
        #expect(onBlack.gray == 1)
        #expect(onWhite.alpha < 0.25 && onBlack.alpha < 0.25, "Faint, never a solid line.")
    }

    @Test func theBandIsEvenAtTheCornersToo() throws {
        let tile = Placement(role: .camera, crop: .zero, frame: CGRect(x: 0, y: 0, width: 200, height: 300), corners: Corners(all: 40), borderWidth: 4)
        let mask = try #require(TileShape.borderMask(for: tile, size: tile.frame.size, width: 4))
        let context = try #require(CGContext(data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 200, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.draw(mask, in: CGRect(x: 0, y: 0, width: 200, height: 300))
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        func value(_ x: Int, _ y: Int) -> Int { Int(bytes[y * 200 + x]) }
        /// How many pixels are lit along a line from a point inward.
        func lit(from start: (Int, Int), step: (Int, Int)) -> Int {
            var count = 0
            var point = start
            for _ in 0..<40 {
                if point.0 < 0 || point.1 < 0 || point.0 >= 200 || point.1 >= 300 { break }
                if value(point.0, point.1) > 128 { count += 1 }
                point = (point.0 + step.0, point.1 + step.1)
            }
            return count
        }
        let side = lit(from: (0, 150), step: (1, 0))
        #expect(side == 4, "Four pixels on the straight edge, got \(side).")
        // Crossing the corner on its diagonal, where the curve faces 45°, each step moves √2 px, so a 4 px band is
        // about 2.8 steps: 2 or 3 pixels lit past the antialiased edge. The old cut-out band was thicker there.
        let diagonal = lit(from: (0, 0), step: (1, 1))
        #expect(diagonal >= 2 && diagonal <= 3, "About 2.8 diagonal steps across the corner, got \(diagonal).")
        #expect(value(100, 150) < 20, "Clear inside.")
    }
}

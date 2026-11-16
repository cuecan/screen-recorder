import CoreGraphics
import Foundation
import Testing
import ProjectKit
@testable import RenderKit

/// The camera's framing in the layouts (docs/decisions.md, 52): every camera slot is cropped around the
/// framing's point, each keeping its own shape.
@Suite struct CameraFramingGeometryTests {
    let camera = CGSize(width: 1920, height: 1080)

    @Test func fourByThreeAndPortraitCamerasKeepTheirShapeInEverySlot() throws {
        for camera in [CGSize(width: 1440, height: 1080), CGSize(width: 1080, height: 1920)] {
            let pictures = ClipPictures(screen: CGSize(width: 1215, height: 1080), camera: camera,
                                        cameraFramings: .everywhere(CameraFraming(centerX: 0.6, centerY: 0.4, zoom: 1.5)),
                                        recordedLayout: .sideBySide(.nineByEight))
            for output in OutputShape.allCases {
                let placement = try #require(LayoutGeometry.frame(for: .automatic, in: output, pictures: pictures).placement(.camera))
                let cropAspect = placement.crop.width * camera.width / (placement.crop.height * camera.height)
                #expect(abs(cropAspect - placement.frame.width / placement.frame.height) < 0.00001)
            }
        }
    }

    @Test func unzoomedAndCentredIsTheOldCrop() {
        let slot = CGSize(width: 640, height: 1080)
        #expect(LayoutGeometry.framedCrop(source: camera, into: slot, framing: .centered) == LayoutGeometry.fillCrop(source: camera, into: slot))
    }

    @Test func zoomingShrinksTheCropAroundThePoint() {
        let slot = CGSize(width: 1080, height: 1080)
        let framing = CameraFraming(centerX: 0.6, centerY: 0.4, zoom: 2)
        let crop = LayoutGeometry.framedCrop(source: camera, into: slot, framing: framing)
        let whole = LayoutGeometry.fillCrop(source: camera, into: slot)
        #expect(abs(crop.width - whole.width / 2) < 0.0001)
        #expect(abs(crop.height - 0.5) < 0.0001)
        #expect(abs(crop.midX - 0.6) < 0.0001)
        #expect(abs(crop.midY - 0.4) < 0.0001)
        // The crop keeps the slot's shape in pixels.
        #expect(abs((crop.width * camera.width) / (crop.height * camera.height) - 1) < 0.001)
    }

    @Test func theCropStaysOnThePicture() {
        let framing = CameraFraming(centerX: 0.98, centerY: 0.02, zoom: 1.5)
        let crop = LayoutGeometry.framedCrop(source: camera, into: CGSize(width: 1080, height: 960), framing: framing)
        #expect(crop.minX >= 0 && crop.maxX <= 1.0001)
        #expect(crop.minY >= 0 && crop.maxY <= 1.0001)
        #expect(abs(crop.maxX - 1) < 0.0001, "As close to the point as the edge allows.")
        #expect(crop.minY == 0)
    }

    @Test func everyCameraSlotFollowsItsOwnFramingAndTheScreenDoesnt() throws {
        let split = CameraFraming(centerX: 0.4, centerY: 0.45, zoom: 1.4)
        let bubbleFraming = CameraFraming(centerX: 0.65, centerY: 0.5, zoom: 1.2)
        let framings = CameraFramings([.split: split, .card: bubbleFraming])
        let both = ClipPictures(screen: CGSize(width: 1215, height: 1080), camera: camera, cameraFramings: framings,
                                recordedLayout: .sideBySide(.nineByEight))
        let video = try #require(LayoutGeometry.frame(for: .automatic, in: .landscape, pictures: both).placement(.camera))
        #expect(video.cameraSlot == .split)
        #expect(abs(video.crop.midY - 0.45) < 0.0001)
        let shortFrame = LayoutGeometry.frame(for: .automatic, in: .vertical, pictures: both)
        let short = try #require(shortFrame.placement(.camera))
        #expect(short.cameraSlot == .split)
        #expect(abs(short.crop.midY - 0.45) < 0.0001, "One framing: the Short crops its wide slot around the same point.")
        #expect(short.crop.size != video.crop.size, "Each shape crops its own slot's shape.")
        #expect(shortFrame.placement(.screen)?.crop == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(shortFrame.placement(.screen)?.cameraSlot == nil)
        // The corner bubble, in both outputs.
        let screen = ClipPictures(screen: CGSize(width: 1920, height: 1080), camera: camera, cameraFramings: framings)
        for output in OutputShape.allCases {
            let frame = LayoutGeometry.frame(for: .card(.bubble), in: output, pictures: screen)
            let bubble = try #require(frame.placement(.camera))
            #expect(bubble.cameraSlot == .card)
            #expect(abs(bubble.crop.midX - 0.65) < 0.0001, "\(output)")
        }
        // A full-screen camera, not framed yet, follows Split's, in both shapes.
        let fullVideo = try #require(LayoutGeometry.frame(for: .camera, in: .landscape, pictures: screen).placement(.camera))
        #expect(fullVideo.cameraSlot == .fullScreen)
        #expect(abs(fullVideo.crop.midY - 0.45) < 0.0001)
        let fullShort = try #require(LayoutGeometry.frame(for: .camera, in: .vertical, pictures: screen).placement(.camera))
        #expect(abs(fullShort.crop.midY - 0.45) < 0.0001)
    }

    @Test func noFaceInABlankVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "framing-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await SyntheticMedia.writeVideo(.init(red: 40, green: 40, blue: 40), width: 640, height: 360, seconds: 1, to: url)
        #expect(try await FaceLocator.face(in: url, samples: 2) == nil)
    }

    @Test func theMedianFaceIgnoresOneThatLookedAway() throws {
        let faces = [
            FaceLocator.Face(box: CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.30)),
            FaceLocator.Face(box: CGRect(x: 0.42, y: 0.31, width: 0.20, height: 0.30)),
            FaceLocator.Face(box: CGRect(x: 0.05, y: 0.70, width: 0.10, height: 0.15)),
        ]
        let median = try #require(FaceLocator.median(of: faces))
        // Middles at x 0.50, 0.52 and 0.10, and y 0.45, 0.46 and 0.775: the odd one out doesn't pull it.
        #expect(abs(median.center.x - 0.50) < 0.0001)
        #expect(abs(median.center.y - 0.46) < 0.0001)
    }
}

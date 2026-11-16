import CoreGraphics
import Foundation
import ProjectKit
import Testing
@testable import RenderKit

/// The layouts in the FCPXML (docs/decisions.md, 60 and 66): each camera placed where the preview puts it,
/// and Mirror as a negative scale.
struct FCPXMLLayoutTests {
    private let frame = CGSize(width: 1920, height: 1080)
    private let camera = CGSize(width: 1920, height: 1080)

    /// The numbers in an attribute, such as `position="12.5 -3"`.
    private func values(_ attribute: String, in xml: String) -> [Double] {
        guard let range = xml.range(of: "\(attribute)=\"") else { return [] }
        let rest = xml[range.upperBound...]
        return rest.prefix { $0 != "\"" }.split(separator: " ").compactMap { Double($0) }
    }

    @Test func mirrorFlipsTheScaleAndTheCropsOffset() {
        let crop = CGRect(x: 0.5, y: 0.1, width: 0.4, height: 0.8)
        let slot = CGRect(x: 1400, y: 200, width: 400, height: 600)
        let plain = FCPXMLWriter.transform(Placement(role: .camera, crop: crop, frame: slot), picture: camera, frame: frame)
        let mirrored = FCPXMLWriter.transform(Placement(role: .camera, crop: crop, frame: slot, mirrored: true), picture: camera, frame: frame)
        let scale = values("scale", in: plain), flipped = values("scale", in: mirrored)
        #expect(flipped[0] == -scale[0] && flipped[1] == scale[1])
        // The slot's middle, 1600 px across, is 640 px right of the frame's: the crop's middle, 0.2 of the
        // fitted picture right of its own, moves the clip left when plain and right when mirrored, by the same.
        let unit = frame.height / 100
        let middle = (slot.midX - frame.width / 2) / unit
        let position = values("position", in: plain)[0], flippedPosition = values("position", in: mirrored)[0]
        #expect(abs((position + flippedPosition) / 2 - middle) < 0.001)
        #expect(flippedPosition > position)
        #expect(values("position", in: plain)[1] == values("position", in: mirrored)[1])
    }

    @Test func everyPresetsCameraLandsWhereThePreviewPutsIt() {
        let pictures = ClipPictures(screen: CGSize(width: 1500, height: 1000), camera: camera, recordedLayout: .card(.standard))
        for output in OutputShape.allCases {
            let size = CGSize(width: output.width, height: output.height)
            for destination in VideoFormat.Destination.allCases {
                for preset in takeLayouts(for: destination) {
                    let layout = LayoutGeometry.frame(for: preset.layout, in: output, pictures: pictures,
                                                      look: OutputLook(mirror: true))
                    guard let placement = layout.placement(.camera) else {
                        Issue.record("\(preset) has no camera")
                        continue
                    }
                    #expect(placement.mirrored)
                    let xml = FCPXMLWriter.transform(placement, picture: camera, frame: size)
                    // Scale times the fitted width of the crop is the slot's width.
                    let fit = min(size.width / camera.width, size.height / camera.height)
                    let scale = abs(values("scale", in: xml)[0])
                    #expect(abs(scale * placement.crop.width * camera.width * fit - placement.frame.width) < 0.5, "\(preset) in \(output)")
                    #expect(values("scale", in: xml)[0] < 0)
                }
            }
        }
    }
}

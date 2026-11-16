import AppKit
import CoreGraphics
import ProjectKit
import RenderKit

extension RecorderModel {
    /// Shared by the previews and the framing guides. Camera-off keeps its placeholder slot;
    /// camera-only recording has no screen slot. Dimensions follow the selected camera format. The take
    /// is drawn in the chosen preset (docs/decisions.md, 66).
    var previewPictures: ClipPictures {
        let screen = recordsScreen ? format.map { CGSize(width: 1000 * $0.captureRatio.aspect, height: 1000) } : nil
        return ClipPictures(screen: screen, camera: cameraPictureSize, cameraFramings: framings, recordedLayout: format?.layout,
                            screenPointHeight: format.flatMap { screenPointHeight(for: $0.captureRatio) })
    }

    /// The height in points of the area a shape would record: the area on screen when it has that shape,
    /// otherwise the largest one the chosen display fits. It sets the screen's corners, a window's in the
    /// recording's own scale (docs/decisions.md, 67).
    func screenPointHeight(for shape: CaptureArea.Ratio) -> Double? {
        if let placement = area.placement, placement.area.ratio == shape { return Double(placement.area.heightPoints) }
        guard let visible = (area.placement?.visibleFrame ?? (NSScreen.with(id: area.selectedDisplayID) ?? NSScreen.main)?.visibleFrame) else { return nil }
        return CaptureArea.largest(shape, fittingWidth: visible.width, height: visible.height).map { Double($0.heightPoints) }
    }

    /// One output of the take as it will start: the chosen preset in the look it starts with.
    func previewFrame(in output: OutputShape) -> FrameLayout {
        LayoutGeometry.frame(for: .automatic, in: output, pictures: previewPictures, look: look)
    }

    /// The kinds of camera slot the chosen format's layouts use, in the order the preview shows them:
    /// the slots the framing popover offers as tabs. Empty with no format, or no camera.
    var formatCameraSlots: [CameraSlot] {
        guard let format else { return [] }
        var slots: [CameraSlot] = []
        for output in format.outputs {
            for placement in previewFrame(in: output).placements {
                if let slot = placement.cameraSlot, !slots.contains(slot) { slots.append(slot) }
            }
        }
        return slots
    }

    /// Where the camera will cover the screen, for the area's shading while setting up and recording
    /// (docs/decisions.md, 89): the part of the screen under the card. Nil for Side by side, and with no screen.
    var cameraCover: LayoutGeometry.Cover? {
        guard recordsScreen, let format else { return nil }
        return format.outputs.lazy.compactMap { LayoutGeometry.cover(format.layout, shape: format.captureRatio, in: $0, look: self.look) }.first
    }
}

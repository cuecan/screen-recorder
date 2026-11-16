import AppKit
import AVFoundation
import Observation
import ProjectKit
import RenderKit
import SwiftUI

/// Frame the camera… in the editor: the Recording Panel's own framing popover (docs/ui.md, R8 and E5),
/// over a frame of the recorded camera at the playhead, framing the edit's slots (docs/decisions.md, 52).
///
/// While dragging, scrolling or sliding, the change shows at once in the popover; when the gesture ends
/// it's saved as one edit, the same change `set_camera_framing` makes, so the preview rebuilds once and
/// History gets one line, not one per mouse movement.
@Observable
final class EditorFramingSource: FramingSource {
    /// Weak: the editor's model keeps its framing sources.
    @ObservationIgnored private weak var model: EditorModel?
    let source: SourceID
    private(set) var still: CGImage?
    /// Changes shown but not yet saved, by slot.
    private var pending: [CameraSlot: CameraFraming] = [:]
    @ObservationIgnored private(set) lazy var popover = CameraFramingPopover(source: self)

    init(model: EditorModel, source: SourceID) {
        self.model = model
        self.source = source
    }

    var cameraPictureSize: CGSize {
        let video = model?.project?.source(source)?.track(.camera)?.media.video
        return CGSize(width: video?.width ?? 1920, height: video?.height ?? 1080)
    }

    var framingPicture: FramingPicture { .still(still) }

    func shownFraming(_ slot: CameraSlot) -> CameraFraming {
        if let framing = pending[slot] { return framing }
        return model?.edit?.framings(for: source).framing(for: slot) ?? .centered
    }

    func setFraming(_ framing: CameraFraming, slot: CameraSlot) {
        pending[slot] = framing
    }

    func framingEnded(slot: CameraSlot) {
        guard let model, let framing = pending[slot] else { return }
        let saved = model.edit?.framings(for: source)[slot]
        if framing != saved { model.setFraming(framing, slot: slot, for: source) }
    }

    /// The shape the editor shows, named in the popover when the take is made for both.
    var shapeShown: OutputShape? { (model?.outputs.count ?? 0) > 1 ? model?.shape : nil }

    /// The camera in a slot as the shape shown crops it, from the edit's own clips, layouts and looks. A
    /// framing is the same in both shapes (docs/decisions.md, 77); to see the other's crop, flip the toggle.
    func cameraPlacements(in slot: CameraSlot) -> [(output: OutputShape, placement: Placement)] {
        placements.filter { $0.placement.cameraSlot == slot }
    }

    /// The kinds of slot the edit shows this camera in, for the popover's tabs.
    var usedSlots: [CameraSlot] {
        let used = Set(placements.compactMap(\.placement.cameraSlot))
        return CameraSlot.allCases.filter { used.contains($0) }
    }

    /// The shown shape's first camera placement in each kind of slot, over the source's clips.
    private var placements: [(output: OutputShape, placement: Placement)] {
        guard let model, let edit = model.edit, let info = model.project?.source(source) else { return [] }
        let pictures = ClipPictures(source: info, cameraFramings: pendingFramings(edit))
        var found: [(output: OutputShape, placement: Placement)] = []
        for output in [model.shape] {
            for clip in edit.main where clip.source == source {
                let frame = LayoutGeometry.frame(for: clip.layout, in: output, pictures: pictures, look: edit.look(of: clip))
                for placement in frame.placements {
                    guard let slot = placement.cameraSlot, !found.contains(where: { $0.output == output && $0.placement.cameraSlot == slot }) else { continue }
                    found.append((output, placement))
                }
            }
        }
        return found
    }

    /// The edit's framings with what's being changed now on top, so the outlines follow the pointer.
    private func pendingFramings(_ edit: Edit) -> CameraFramings {
        var framings = edit.framings(for: source)
        for (slot, framing) in pending { framings[slot] = framing }
        return framings
    }

    /// Opens the popover beside `anchor`, in screen coordinates, on the first slot the edit uses.
    func open(beside anchor: CGRect) {
        pending = [:]
        let slots = usedSlots
        popover.open(beside: anchor, slot: slots.first ?? .fullScreen, tabs: slots)
        Task { await loadStill() }
    }

    /// A frame of the camera at the playhead, as recorded.
    private func loadStill() async {
        guard let model, let track = model.project?.source(source)?.track(.camera) else { return }
        let url = track.file.url(relativeTo: model.folder.url)
        let time = max(0, (model.edit?.sourceTime(at: model.currentTime)?.time ?? 1) - track.startOffset)
        still = await Task.detached { () -> CGImage? in
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 864, height: 864)
            return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        }.value
    }
}

/// Where a view is on screen, for opening a panel beside it.
struct ScreenFrameReader: NSViewRepresentable {
    @Binding var frame: CGRect

    func makeNSView(context: Context) -> NSView { Reader(frame: $frame) }
    func updateNSView(_ view: NSView, context: Context) { (view as? Reader)?.report() }

    final class Reader: NSView {
        var frame_: Binding<CGRect>
        init(frame: Binding<CGRect>) {
            frame_ = frame
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            report()
        }
        func report() {
            guard let window else { return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            if rect != frame_.wrappedValue { DispatchQueue.main.async { self.frame_.wrappedValue = rect } }
        }
    }
}

#if DEBUG
extension EditorFramingSource {
    /// Loads the camera frame at once, for Xcode's previews, which don't wait.
    func loadStillForPreview(at time: TimeInterval) {
        guard let model, let track = model.project?.source(source)?.track(.camera) else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: track.file.url(relativeTo: model.folder.url)))
        generator.maximumSize = CGSize(width: 864, height: 864)
        still = try? generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    }
}
#endif

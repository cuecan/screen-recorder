import AVFoundation
import Foundation
import ProjectKit

extension BuiltComposition {
    /// Redraws static screen/camera framing over the existing media tracks. Call only when the inputs
    /// differ in framing alone (``RenderInputs/differsOnlyInFraming(from:)``). Audio, freezes, overlays,
    /// captions and time mappings remain the original composition's.
    public func reframed(using inputs: RenderInputs) -> BuiltComposition {
        let updated = EditTimeline(edit: inputs.edit, transcripts: inputs.transcripts)
        let instructions = videoComposition.instructions.compactMap { original -> LayoutInstruction? in
            guard let original = original as? LayoutInstruction else { return nil }
            let middle = original.timeRange.start.seconds + original.timeRange.duration.seconds / 2
            guard let index = updated.clipIndex(at: middle) else { return original }
            let clip = updated.clips[index].clip
            guard let source = inputs.project.source(clip.source) else { return original }
            let pictures = ClipPictures(source: source, cameraFramings: inputs.edit.framings(for: source.id))
            let redrawn = original.panels.enumerated().map { index, panel in
                guard panels.indices.contains(index) else { return panel }
                let output = panels[index].output
                let frame = LayoutGeometry.frame(for: clip.layout, in: output, pictures: pictures,
                    scale: panel.rect.height / Double(output.height), look: inputs.edit.look(of: clip),
                    screenTransform: clip.screenTransform, cameraTransform: clip.cameraTransform)
                var panel = panel
                panel.items = panel.items.map { item in
                    guard case .track(let placement, let id) = item,
                          placement.role == .screen || placement.role == .camera,
                          let changed = frame.placement(placement.role) else { return item }
                    return .track(changed, id)
                }
                return panel
            }
            return LayoutInstruction(timeRange: original.timeRange, panels: redrawn, renderSize: original.renderSize, stills: original.stills)
        }
        let video = AVVideoComposition(configuration: AVVideoComposition.Configuration(
            customVideoCompositorClass: LayoutCompositor.self, frameDuration: videoComposition.frameDuration,
            instructions: instructions, renderSize: videoComposition.renderSize))
        return BuiltComposition(composition: composition, videoComposition: video, audioMix: audioMix,
                                timeline: updated, panels: panels, audioTrackIDs: audioTrackIDs)
    }
}

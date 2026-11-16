import Foundation
import ProjectKit
import RenderKit

extension EditorModel {
    /// Show the recording's name in the editor; source ids belong to the edit file and tools.
    func displayName(of overlay: Overlay) -> String {
        if case .source(let id) = overlay.media { return project?.source(id)?.name ?? "Recording" }
        return overlay.name
    }

    /// Resets the controls in the Layout section together. Framing, captions and sound belong to
    /// separate sections, so a section reset must leave them alone.
    func resetClipLayout(for ids: Set<ClipID>) {
        let project = project
        change("Reset clip layout") { edit, _ in
            for id in ids {
                guard let clip = edit.main.first(where: { $0.id == id }) else { continue }
                try edit.setLayout(.automatic, for: id, recorded: project?.source(clip.source)?.layout)
                try edit.changeLook(for: id) { $0.cameraSide = .standard }
            }
        }
    }

    /// Clips whose source contains the chosen picture; missing camera/screen tracks are never invented.
    func clips(with picture: Edit.Picture) -> [Clip] {
        selectedClips.filter { project?.source($0.source)?.track(picture == .screen ? .screen : .camera) != nil }
    }

    /// The clip override, or the take's framing for the layout currently shown.
    func transform(of clip: Clip, picture: Edit.Picture) -> PictureTransform {
        guard let source = project?.source(clip.source), let edit else { return .identity }
        return LayoutGeometry.transform(of: picture, clip: clip, source: source, edit: edit, in: shape)
    }

    /// Changes only the parameter touched. Mixed selections keep their other centres and zooms.
    func setTransform(picture: Edit.Picture, centerX: Double? = nil, centerY: Double? = nil, zoom: Double? = nil) {
        let ids = clips(with: picture).map(\.id)
        guard !ids.isEmpty, let project else { cancelTransformPreview(); return }
        let output = shape
        var changed = false
        let saved = change("Reframed \(picture.rawValue) in \(ids.count == 1 ? "clip" : "\(ids.count) clips")") { edit, _ in
            // Read the current values under the mutation lock. A second gesture can finish before the
            // asynchronous preview reload publishes the first, and must not overwrite its parameters.
            for id in ids {
                guard let clip = edit.main.first(where: { $0.id == id }) else { throw EditError.unknownClip(id) }
                guard let source = project.source(clip.source) else { throw EditError.unknownSource(clip.source) }
                let current = LayoutGeometry.transform(of: picture, clip: clip, source: source, edit: edit, in: output)
                let transform = current.changing(centerX: centerX, centerY: centerY, zoom: zoom)
                if transform != current {
                    try edit.setTransform(transform, picture: picture, for: [id])
                    changed = true
                }
            }
        }
        // Returning to the saved value schedules no reload, so restore the picture explicitly.
        if saved, changed { finishTransformPreview() } else { cancelTransformPreview() }
    }

    func resetTransform(picture: Edit.Picture) {
        finishTransformPreview()
        let ids = clips(with: picture).map(\.id)
        guard !ids.isEmpty else { return }
        change("Reset \(picture.rawValue) framing") { edit, _ in try edit.setTransform(nil, picture: picture, for: ids) }
    }
}

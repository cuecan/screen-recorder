import ProjectKit
import RenderKit
import SwiftUI

/// Static screen/camera framing belongs to the selected clips. The take's camera framing is a default
/// rather than a side effect of zooming a single shot.
struct ClipTransformInspector: View {
    let model: EditorModel
    let picture: Edit.Picture
    @State private var framingAnchor = CGRect.zero

    private var clips: [Clip] { model.clips(with: picture) }
    private var transforms: [PictureTransform] { clips.map { model.transform(of: $0, picture: picture) } }
    private var title: String { picture == .screen ? "Screen framing" : "Camera framing" }
    private var hasOverride: Bool {
        clips.contains { picture == .screen ? $0.screenTransform != nil : $0.cameraTransform != nil }
    }
    private var isVisible: Bool {
        clips.contains { clip in
            guard let source = model.project?.source(clip.source), let edit = model.edit else { return false }
            let frame = LayoutGeometry.frame(for: clip.layout, in: model.shape, pictures: ClipPictures(source: source), look: edit.look(of: clip))
            return frame.placement(picture == .screen ? .screen : .camera) != nil
        }
    }

    var body: some View {
        if !clips.isEmpty, isVisible {
            InspectorSection(title, summary: shared(\.zoom).map { "\(Int(($0 * 100).rounded()))%" } ?? "Mixed",
                             canReset: hasOverride, reset: { model.resetTransform(picture: picture) }) {
                InspectorSlider(title: "Zoom", value: shared(\.zoom).map { $0 * 100 }, range: 100...300, unit: "%", preview: {
                    model.previewTransform(picture: picture, zoom: $0 / 100)
                }, cancelPreview: { model.cancelTransformPreview() }) {
                    model.setTransform(picture: picture, zoom: $0 / 100)
                }
                InspectorRow("Center") {
                    HStack(spacing: 5) {
                        Text("X").foregroundStyle(.secondary)
                        InspectorNumberField(title: "\(title) center X", value: shared(\.centerX).map { $0 * 100 },
                                             range: 0...100, step: 0.5, fractionDigits: 1, preview: {
                            model.previewTransform(picture: picture, centerX: $0 / 100)
                        }, cancelPreview: { model.cancelTransformPreview() }) {
                            model.setTransform(picture: picture, centerX: $0 / 100)
                        }
                        .frame(minWidth: 38, maxWidth: .infinity, minHeight: 22)
                        Text("Y").foregroundStyle(.secondary)
                        InspectorNumberField(title: "\(title) center Y", value: shared(\.centerY).map { $0 * 100 },
                                             range: 0...100, step: 0.5, fractionDigits: 1, preview: {
                            model.previewTransform(picture: picture, centerY: $0 / 100)
                        }, cancelPreview: { model.cancelTransformPreview() }) {
                            model.setTransform(picture: picture, centerY: $0 / 100)
                        }
                        .frame(minWidth: 38, maxWidth: .infinity, minHeight: 22)
                        Text("%").font(.caption).foregroundStyle(.secondary).frame(width: 18, alignment: .leading)
                    }
                }
                .help("The point kept in the middle of the shot.")
                TransformPositionPad(x: shared(\.centerX), y: shared(\.centerY), preview: { x, y in
                    model.previewTransform(picture: picture, centerX: x, centerY: y)
                }) { x, y in
                    model.setTransform(picture: picture, centerX: x, centerY: y)
                }
                if clips.count != model.selectedClips.count {
                    detail("Applies to \(clips.count) of the selected clips.")
                }
            }
            .onDisappear { model.cancelTransformPreview() }
            if picture == .camera, Set(clips.map(\.source)).count == 1, let source = clips.first?.source {
                InspectorSection("Camera source", summary: "Whole take", expanded: false) {
                    if let info = model.project?.source(source) { detail(info.name) }
                    Button("Default framing for this take…") { model.framing(source).open(beside: framingAnchor) }
                        .background(ScreenFrameReader(frame: $framingAnchor))
                    detail("Source settings apply to every clip from this take.")
                }
            }
        }
    }

    private func shared(_ keyPath: KeyPath<PictureTransform, Double>) -> Double? {
        let values = transforms.map { $0[keyPath: keyPath] }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

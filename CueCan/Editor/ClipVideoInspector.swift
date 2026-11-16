import ProjectKit
import RenderKit
import SwiftUI

/// The clip's picture settings, grouped in the order they affect its image.
struct ClipVideoInspector: View {
    let model: EditorModel

    private var clips: [Clip] { model.selectedClips }
    private var ids: Set<ClipID> { Set(clips.map(\.id)) }
    private var layouts: [ProjectKit.Layout] {
        clips.compactMap { clip in
            model.project?.source(clip.source).map { LayoutGeometry.resolved(clip.layout, in: model.shape, pictures: ClipPictures(source: $0)) }
        }
    }
    private var sharedLayout: ProjectKit.Layout? {
        guard LayoutChoice.shared(in: layouts) != nil else { return nil }
        return layouts.first
    }

    var body: some View {
        if let clip = clips.first, let source = model.project?.source(clip.source) {
            let pictures = ClipPictures(source: source)
            let destination = model.project?.effectiveFormat.destination ?? .landscape
            let recorded = model.project?.source(clip.source)?.layout
            InspectorSection("Layout", summary: sharedLayout?.name ?? "Mixed",
                             canReset: clips.contains { $0.layout != .automatic || $0.look.cameraSide != .standard },
                             reset: { model.resetClipLayout(for: ids) }) {
                LayoutTiles(output: model.shape, destination: destination, pictures: pictures,
                            look: model.edit?.look(of: clip) ?? .plain, current: sharedLayout) {
                    model.setLayout($0, for: ids)
                }
                .padding(.bottom, 4)
                if !layouts.isEmpty, layouts.allSatisfy({ $0 == .sideBySide }) {
                    InspectorRow("Camera side") {
                        // Left then Right, Above then Below, as they sit in the frame.
                        let sides: [OutputLook.CameraSide] = model.shape == .landscape ? [.flipped, .standard] : [.standard, .flipped]
                        Picker("Camera side", selection: Binding(get: { model.sharedClipValue(\.look.cameraSide) }, set: { value in
                            if let value { model.setClipLook("Changed camera side", for: ids) { $0.cameraSide = value } }
                        })) {
                            ForEach(sides, id: \.self) { Text($0.label(in: model.shape)).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    if destination != .both, case .sideBySide(let shape) = recorded {
                        InspectorRow("Camera") {
                            Text("\(TakeLayout.shareLabel(shape, for: destination)) of the \(destination == .vertical ? "height" : "width"), as recorded")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help("Set when the take was recorded.")
                        }
                    }
                }
                let cards = layouts.compactMap(\.card)
                if !cards.isEmpty, cards.count == layouts.count {
                    CardControls(cards: cards, offersScreen: model.shape == .landscape) { reason, body in
                        model.changeCards(reason, for: ids, body)
                    }
                }
            }
            ClipTransformInspector(model: model, picture: .screen)
            ClipTransformInspector(model: model, picture: .camera)
            ClipSpeedInspector(model: model, ids: ids)
            ClipCaptionsInspector(model: model)
        }
    }
}

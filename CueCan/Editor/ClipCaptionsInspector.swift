import ProjectKit
import SwiftUI

/// Caption visibility is a clip setting; its style is shared by the edit.
struct ClipCaptionsInspector: View {
    let model: EditorModel

    var body: some View {
        let clips = model.selectedClips
        let ids = Set(clips.map(\.id))
        let captions = model.edit?.captions ?? Captions()
        InspectorSection("Captions", summary: model.sharedClipValue(\.look.captions).map { $0 ? "On" : "Off" } ?? "Mixed") {
            InspectorToggle(title: "Show captions", value: model.sharedClipValue(\.look.captions)) { on in
                model.setClipLook(on ? "Captions on" : "Captions off", for: ids) { $0.captions = on }
            }
            .frame(height: 22)
            if clips.contains(where: \.look.captions) {
                InspectorRow("Style") {
                    Picker("Style", selection: Binding(get: { captions.styleName }, set: { name in
                        model.setCaptions("Caption style \(name)") { $0.setStyle(named: name) }
                    })) {
                        ForEach(CaptionStyle.catalog(for: .landscape).map(\.name), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                detail("The style applies to the whole project.")
            }
        }
    }
}

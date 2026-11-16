import ProjectKit
import SwiftUI

/// Caption visibility is a clip setting; its single style and timing are shared by the edit.
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
                InspectorRow("Style") { Text(captions.styleName) }
                detail("Style and timing apply to the whole project.")
                DisclosureGroup("Timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        InspectorRow("Show earlier") {
                            InspectorNumberField(title: "Caption timing offset", value: captions.timing.lead * 1000,
                                                 range: -500...500, step: 10) { value in
                                model.setCaptions("Caption timing \(Int(value)) ms") { $0.timing.lead = value / 1000 }
                            }
                            .frame(width: 62, height: 22)
                            Text("ms").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.callout)
            }
        }
    }
}

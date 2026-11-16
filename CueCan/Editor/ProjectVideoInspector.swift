import ProjectKit
import SwiftUI

/// Project-wide appearance is part of the inspector, beside the clip controls that use it.
struct ProjectVideoInspector: View {
    let model: EditorModel

    var body: some View {
        let look = model.edit?.look ?? EditLook()
        InspectorSection("Appearance", canReset: !look.hasStartingAppearance, reset: {
            model.setLook("Reset project appearance") { $0.resetAppearance() }
        }) {
            InspectorRow("Inset") {
                Picker("Inset", selection: Binding(get: { look.inset }, set: { value in
                    model.setLook("Inset \(value.label)") { $0.inset = value }
                })) {
                    ForEach(OutputLook.Inset.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            .help("The space around the screen and the camera.")
            InspectorToggle(title: "Rounded corners", value: look.rounded) { value in
                model.setLook(value ? "Rounded corners" : "Square corners") { $0.rounded = value }
            }
            .frame(height: 22)
            .help("Cards have their own Roundness.")
            InspectorToggle(title: "Mirror camera", value: look.mirror) { value in
                model.setLook(value ? "Mirrored camera" : "Not mirrored") { $0.mirror = value }
            }
            .frame(height: 22)
            .help("Mirrors the camera in every clip.")
        }
        BackgroundInspector(model: model)
        InspectorSection("Project", summary: model.project?.effectiveFormat.destinationLabel, expanded: false, storageKey: "projectSummary") {
            InspectorRow("Format") { Text(model.project?.effectiveFormat.destinationLabel ?? "16:9") }
            InspectorRow("Duration") { Text(model.clock(model.duration)).monospacedDigit() }
            InspectorRow("Frame rate") { Text("\(Int((1 / model.frameDuration).rounded())) fps") }
            detail("Select a clip to change its layout and framing.")
        }
    }
}

import ProjectKit
import SwiftUI

/// One predictable home for project and clip settings. The tab stays put while the selection changes;
/// the header identifies the scope. Transcript remains directly reachable while inspecting a clip.
struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $model.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .accessibilityIdentifier("editor.inspector.tabs")
            Divider()
            if model.inspectorTab != .transcript {
                InspectorBreadcrumbs(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                Divider()
            }
            if model.inspectorTab == .transcript {
                TranscriptInspector(model: model)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.inspectorTab == .info {
                            InformationInspector(model: model)
                        } else if !model.selectedClips.isEmpty {
                            if model.inspectorTab == .video {
                                ClipVideoInspector(model: model)
                            } else {
                                ClipAudioInspector(model: model)
                            }
                        } else if let overlay = model.selectedOverlay {
                            OverlayInspector(model: model, overlay: overlay)
                        } else if let freeze = model.selectedFreeze {
                            FreezeInspector(model: model, freeze: freeze)
                        } else if model.selection.overlayIDs.count > 1 {
                            ContentUnavailableView("Multiple overlays", systemImage: "square.stack",
                                                   description: Text("Select one overlay to change its settings."))
                        } else if model.inspectorTab == .video {
                            ProjectVideoInspector(model: model)
                        } else {
                            ProjectAudioInspector(model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .controlSize(.small)
        .disabled(model.edit == nil)
    }
}

/// Supporting detail used by the overlay, hold and audio controls.
func detail(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
    }
}

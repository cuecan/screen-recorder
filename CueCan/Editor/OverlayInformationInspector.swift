import AppKit
import ProjectKit
import SwiftUI

struct OverlayInformationInspector: View {
    let model: EditorModel
    let overlay: Overlay

    var body: some View {
        let pieces = model.timeline?.overlays.filter { $0.overlay.id == overlay.id } ?? []
        InspectorSection("Overlay", storageKey: "overlayInformation") {
            Text(model.displayName(of: overlay)).font(.callout.weight(.semibold)).textSelection(.enabled)
            InspectorRow("Type") { Text(overlay.isStill ? "Still image" : "Video") }
            InspectorRow("Duration") { Text(model.clock(pieces.reduce(0) { $0 + $1.timeline.duration })).monospacedDigit() }
            if let first = pieces.first, let last = pieces.last {
                InspectorRow("Start") { Text(model.clock(first.timeline.start)).monospacedDigit() }
                InspectorRow("End") { Text(model.clock(last.timeline.end)).monospacedDigit() }
                if pieces.count > 1 { InspectorRow("Stretches") { Text("\(pieces.count)") } }
            } else { detail("This overlay's anchor is not currently in the edit.") }
            if !overlay.isStill {
                InspectorRow("Source in") { Text(model.clock(overlay.sourceIn)).monospacedDigit() }
            }
            if case .file(let file, _) = overlay.media {
                let url = file.url(relativeTo: model.folder.url)
                Text(url.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Reveal file in Finder", systemImage: "doc") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }
}

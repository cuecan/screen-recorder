import AppKit
import ProjectKit
import SwiftUI

/// Facts about the selected clips or project, kept apart from editable picture and sound parameters.
struct InformationInspector: View {
    let model: EditorModel

    private var sources: [Source] {
        guard let project = model.project else { return [] }
        if model.selection.isEmpty { return project.sources }
        var ids = Set(model.selectedClips.map(\.source))
        if let range = model.selection.wordRange, let transcript = try? model.transcripts.transcript(containing: range) { ids.insert(transcript.source) }
        if let freeze = model.selectedFreeze { ids.insert(freeze.source) }
        if let overlay = model.selectedOverlay, case .source(let id) = overlay.media { ids.insert(id) }
        return project.sources.filter { ids.contains($0.id) }
    }

    var body: some View {
        if let overlay = model.selectedOverlay {
            OverlayInformationInspector(model: model, overlay: overlay)
        } else if let hold = model.selectedFreeze {
            InspectorSection("Hold", storageKey: "holdInformation") {
                InspectorRow("Source in") { Text(model.clock(hold.range.start)).monospacedDigit() }
                InspectorRow("Source out") { Text(model.clock(hold.range.end)).monospacedDigit() }
                InspectorRow("Held frame") { Text(model.clock(hold.frame)).monospacedDigit() }
                detail("Source times in \(model.project?.source(hold.source)?.name ?? "the recording").")
            }
        } else {
            selectionInformation
        }
        ForEach(sources, id: \.id) { source in
            SourceInformationInspector(model: model, source: source, expanded: sources.count == 1)
        }
    }

    private var selectionInformation: some View {
        InspectorSection(model.selection.isEmpty ? "Project" : "Selection", storageKey: "information") {
            if let project = model.project, model.selection.isEmpty {
                Text(project.title).font(.callout.weight(.semibold)).textSelection(.enabled)
                InspectorRow("Created") { Text(project.createdAt, format: .dateTime.month(.abbreviated).day().year()) }
                InspectorRow("Format") { Text(project.effectiveFormat.destinationLabel) }
            }
            InspectorRow("Duration") {
                Text(model.clock(selectionDuration)).monospacedDigit()
            }
            InspectorRow("Frame rate") { Text("\(Int((1 / model.frameDuration).rounded())) fps") }
            if let clip = model.selectedClip, let placed = model.edit?.placements.first(where: { $0.clip.id == clip.id }) {
                InspectorRow("Start") { Text(model.clock(placed.timeline.start)).monospacedDigit() }
                InspectorRow("End") { Text(model.clock(placed.timeline.end)).monospacedDigit() }
                InspectorRow("Source in") { Text(model.clock(clip.playedRange.start)).monospacedDigit() }
                InspectorRow("Source out") { Text(model.clock(clip.playedRange.end)).monospacedDigit() }
            } else if !model.selection.overlayIDs.isEmpty {
                InspectorRow("Overlays") { Text("\(model.selection.overlayIDs.count)") }
            } else if let range = model.selectedRange {
                InspectorRow("Start") { Text(model.clock(range.start)).monospacedDigit() }
                InspectorRow("End") { Text(model.clock(range.end)).monospacedDigit() }
            } else {
                InspectorRow("Clips") { Text("\(model.selectedClips.isEmpty ? model.edit?.main.count ?? 0 : model.selectedClips.count)") }
            }
            Button("Show project in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([model.folder.url]) }
        }
    }

    private var selectionDuration: Double {
        if model.selection.isEmpty { return model.duration }
        if let range = model.selectedRange { return range.duration }
        if !model.selection.overlayIDs.isEmpty {
            return model.timeline?.overlays.filter { model.selection.overlayIDs.contains($0.overlay.id) }.reduce(0) { $0 + $1.timeline.duration } ?? 0
        }
        return model.selectedClips.reduce(0) { $0 + $1.duration }
    }

}

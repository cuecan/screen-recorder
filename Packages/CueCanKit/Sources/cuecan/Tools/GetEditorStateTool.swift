import Foundation
import MCP
import ProjectKit

/// Where the creator is looking in the app (docs/decisions.md, 57).
struct GetEditorStateTool: EditorTool {
    let name = "get_editor_state"
    let description = """
        Where the creator is in CueCan's editor: the playhead, what they selected (clips, overlays, freezes, \
        words) and the range they marked with I and O, each on the edited timeline and in source time, with the \
        words there, and for a take made for both, which shape they have showing (the 16:9 video or the 9:16 \
        Short). Use it for "cut here", "tighten what I selected" or "freeze this bit". Times are for the \
        edit as it was when the app saved them; it says if the edit has changed since.
        """
    var inputSchema: Value { Schema.object(["project": Schema.project], required: ["project"]) }
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        guard let state = try folder.loadEditorState() else {
            return ToolOutput(text: "This project hasn't been open in CueCan's editor, so there's no playhead or selection.")
        }
        let edit = try folder.loadEdit()
        let transcripts = try folder.loadTranscripts()
        var lines: [String] = []
        let age = Int(Date.now.timeIntervalSince(state.updatedAt).rounded())
        lines.append("Saved \(age < 90 ? "\(age) s" : "\(age / 60) min") ago\(state.editRevision == edit.revision ? "" : ", before the edit last changed (revision \(state.editRevision), now \(edit.revision)): times may have moved").")
        if let outputs = (try? folder.loadProject())?.effectiveFormat.outputs, outputs.count > 1 {
            let shape = state.shape.flatMap { outputs.contains($0) ? $0 : nil } ?? outputs[0]
            lines.append("Showing: the \(shape.ratioName) \(shape.title.lowercased()). Every setting is the same in both shapes; preview_frames takes shape.")
        }
        lines.append("Playhead: " + describe(state.playhead, in: edit, transcripts: transcripts))
        if let marked = state.markedRange {
            lines.append("Marked range: \(marked.formatted) of the timeline")
            for piece in edit.sourcePieces(of: marked) {
                let clip = edit.main[piece.index]
                lines.append("  \(clip.id) · \(piece.source) \(piece.range.formatted): \(words(in: piece.range, of: piece.source, transcripts: transcripts))")
            }
        } else if let markIn = state.markIn {
            lines.append("Mark in at \(String(format: "%.2f", markIn)) s, no mark out.")
        }
        let selection = state.selection
        if selection.isEmpty {
            lines.append("Nothing selected.")
        }
        for id in selection.clips {
            guard let placed = edit.placements.first(where: { $0.clip.id == id }) else {
                lines.append("Selected \(id), which isn't in the edit any more.")
                continue
            }
            lines.append("Selected clip \(id): \(placed.timeline.formatted) of the timeline, \(placed.clip.source) \(placed.clip.playedRange.formatted): \(words(in: placed.clip.playedRange, of: placed.clip.source, transcripts: transcripts))")
        }
        for id in selection.overlays {
            if let overlay = edit.overlays.first(where: { $0.id == id }) {
                lines.append("Selected overlay \(id): \(overlay.name), \(overlay.placement.label.lowercased())")
            }
        }
        for id in selection.freezes {
            if let freeze = edit.freezes.first(where: { $0.id == id }) {
                lines.append("Selected freeze \(id): \(freeze.source) \(freeze.range.formatted)")
            }
        }
        if let words = selection.words {
            lines.append("Selected words \(words)")
        }
        if !state.markers.isEmpty {
            lines.append("Markers: " + state.markers.map { String(format: "%.2f s", $0) }.joined(separator: ", "))
        }
        return ToolOutput(text: lines.joined(separator: "\n"))
    }

    private func describe(_ time: TimeInterval, in edit: Edit, transcripts: TranscriptIndex) -> String {
        guard let placed = edit.placement(at: time) else { return String(format: "%.2f s, past the end of the edit.", time) }
        let sourceTime = placed.sourceTime(at: time)
        var text = String(format: "%.2f s on the timeline, in %@, at %@ %.2f s", time, placed.clip.id.description, placed.clip.source.description, sourceTime)
        if let transcript = transcripts[placed.clip.source] {
            if let item = transcript.items.first(where: { $0.start <= sourceTime && sourceTime < $0.end }) {
                switch item {
                case .word(let word): text += ", inside \(word.id) “\(word.text)”"
                case .silence(let silence): text += ", in the pause \(silence.id)"
                }
            }
            let before = transcript.words.last { $0.end <= sourceTime }
            let after = transcript.words.first { $0.start >= sourceTime }
            if let before { text += ", after \(before.id) “\(before.text)”" }
            if let after { text += ", before \(after.id) “\(after.text)”" }
        }
        return text + "."
    }

    private func words(in range: TimeRange, of source: SourceID, transcripts: TranscriptIndex) -> String {
        guard let transcript = transcripts[source] else { return "(not transcribed)" }
        let words = transcript.words.filter { ($0.start + $0.end) / 2 >= range.start && ($0.start + $0.end) / 2 < range.end }
        guard let first = words.first, let last = words.last else { return "no words" }
        return "\(first.id)…\(last.id) “\(EditSummary.shortened(words.map(\.text)))”"
    }
}

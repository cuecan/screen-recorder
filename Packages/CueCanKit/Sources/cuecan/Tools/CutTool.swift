import Foundation
import MCP
import ProjectKit

struct CutTool: EditorTool {
    let name = "cut"
    let description = """
        Removes part of the edit. By id, the usual way: start_id to end_id, a range of words and pauses, from \
        wherever the main track plays them; the cut lands in the real pauses either side. By time, for a cut \
        between words, at a breath, or inside a stretch with no words (most of a wait on screen): start_time \
        and end_time in seconds of the edited timeline (from get_edit or get_editor_state), which removes only \
        what plays there; or with source_id, in seconds of that source's time, from wherever it plays. The rest \
        closes up: there are never gaps.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "start_id": Schema.string("The first word or pause to remove, such as w_12 or s_3."),
                "end_id": Schema.string("The last word or pause to remove. Leave out to remove just start_id."),
                "start_time": Schema.number("Or where to start removing, in seconds of the edited timeline (or of source_id's time)."),
                "end_time": Schema.number("Where to stop removing."),
                "source_id": Schema.string("With start_time and end_time: they're in this source's time, such as src_1."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let target = try EditTarget.read(arguments)
        let folder = try context.folder(arguments)
        let before = try folder.loadEdit()
        let removed: Double
        let edit: Edit
        let what: String
        switch target {
        case .words(let range):
            what = range.description
            (edit, removed) = try context.change(folder, reason: "Cut \(range)") { edit, transcripts in
                try edit.cut(range, transcripts: transcripts)
            }
        case .source(let source, let range):
            what = "\(source) \(range.formatted)"
            (edit, removed) = try context.change(folder, reason: "Cut \(what)") { edit, _ in try edit.cut(source: source, range: range) }
        case .timeline(let range):
            what = range.formatted
            (edit, removed) = try context.change(folder, reason: "Cut \(what) of the timeline") { edit, _ in try edit.cut(timeline: range) }
        }
        let message = removed > 0
            ? "Cut \(what): the edit is \(String(format: "%.2f", removed)) s shorter."
            : "Nothing to cut: \(what) isn't on the timeline, or it's too short once the air around it is kept."
        return try await EditingOutput.afterChecking(message, before: before, edit: edit, folder: folder)
    }
}

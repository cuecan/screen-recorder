import Foundation
import MCP
import ProjectKit

struct KeepTool: EditorTool {
    let name = "keep"
    let description = """
        Puts back part of a source that was cut, next to the clips it was cut from: start_id to end_id by id, or \
        source_id with start_time and end_time in seconds of that source's time.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "start_id": Schema.string("The first word or pause to put back."),
                "end_id": Schema.string("The last word or pause to put back. Leave out for just start_id."),
                "source_id": Schema.string("Or the source to put back time from, such as src_1."),
                "start_time": Schema.number("With source_id: where to start, in seconds of its time."),
                "end_time": Schema.number("With source_id: where to stop."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let target = try EditTarget.read(arguments)
        let folder = try context.folder(arguments)
        let before = try folder.loadEdit()
        let what: String
        let edit: Edit
        let added: Double
        switch target {
        case .words(let range):
            what = range.description
            (edit, added) = try context.change(folder, reason: "Kept \(range)") { edit, transcripts in
                try edit.keep(range, transcripts: transcripts)
            }
        case .timeline:
            throw ToolError.missingArgument("source_id with start_time and end_time")
        case .source(let source, let range):
            let duration = try folder.loadProject().source(source)?.duration
            what = "\(source) \(range.formatted)"
            (edit, added) = try context.change(folder, reason: "Kept \(what)") { edit, _ in
                try edit.keep(source: source, range: range, sourceDuration: duration)
            }
        }
        let message = added > 0 ? "Kept \(what): the edit is \(String(format: "%.2f", added)) s longer." : "\(what) is already on the timeline."
        return try await EditingOutput.afterChecking(message, before: before, edit: edit, folder: folder)
    }
}

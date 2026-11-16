import Foundation
import MCP
import ProjectKit

struct SplitClipTool: EditorTool {
    let name = "split_clip"
    let description = """
        Divides a clip in two, removing nothing, so each part can have its own layout or speed: just before a \
        word (clip_id and before_word_id), or at an exact time on the edited timeline (time), such as the \
        playhead from get_editor_state.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "clip_id": Schema.string("The clip to divide, with before_word_id."),
                "before_word_id": Schema.string("The word the second part starts with."),
                "time": Schema.number("Or where to divide, in seconds of the edited timeline."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let request = try SplitRequest(arguments)
        let folder = try context.folder(arguments)
        let before = try folder.loadEdit()
        switch request {
        case .time(let time):
            let (edit, parts) = try context.change(folder, reason: "Split at \(String(format: "%.2f", time)) s") { edit, _ in
                try edit.split(at: time)
            }
            return try await EditingOutput.afterChecking("Split into \(parts.first.id) and \(parts.second.id).", before: before, edit: edit, folder: folder)
        case .word(let clipID, let word):
        let (edit, parts) = try context.change(folder, reason: "Split \(clipID) before \(word)") { edit, transcripts in
            try edit.split(clipID, before: word, transcripts: transcripts)
        }
        return try await EditingOutput.afterChecking("Split into \(parts.first.id) and \(parts.second.id).", before: before, edit: edit, folder: folder)
        }
    }
}

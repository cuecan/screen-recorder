import Foundation
import MCP
import ProjectKit

struct AddClipTool: EditorTool {
    let name = "add_clip"
    let description = """
        Puts a range of words on the main track as a new clip, from start_word_id to end_word_id of one source. \
        The edges snap to the real pauses around the words, with a little air so no first sound is clipped.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "start_word_id": Schema.string("The first word or pause to play, such as w_12."),
                "end_word_id": Schema.string("The last word or pause to play, such as w_40."),
                "position": Schema.number("Where on the main track, from 0 (first) to the number of clips (last). Leave out to add at the end."),
            ],
            required: ["project", "start_word_id", "end_word_id"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let range = try arguments.range(from: "start_word_id", to: "end_word_id")
        let position = try arguments.optionalInt("position")
        let (edit, clip) = try context.change(folder, reason: "Added \(range) as a clip") { edit, transcripts in
            try edit.addClip(range, at: position, transcripts: transcripts)
        }
        return try EditingOutput.after("Added \(clip.id), \(String(format: "%.2f", clip.duration)) s.", edit: edit, folder: folder)
    }
}

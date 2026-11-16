import Foundation
import MCP
import ProcessingKit
import ProjectKit

/// Fixes what the transcript says (docs/decisions.md, 69): the text replaces the words, and is timed
/// against the audio so its words cut like any others.
struct SetWordTextTool: EditorTool {
    let name = "set_word_text"
    let description = """
        Fixes what the transcript says for a run of words, such as a name it got wrong ("Q can" → "CueCan") or \
        punctuation. start_id to end_id are word ids; the text replaces them. The fix is timed against the \
        audio, so each of its words gets a new id and its own times, and get_transcript shows the fixed words. \
        If the text can't be matched to what was said, the fix is kept as one word that cuts as a whole. To \
        take words out of the video, cut them instead. undo takes a fix back.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "start_id": Schema.string("The first word, such as w_12."),
                "end_id": Schema.string("The last word. Leave out for just start_id."),
                "text": Schema.string("What was said."),
            ],
            required: ["project", "start_id", "text"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let range = try arguments.range(from: "start_id", to: "end_id")
        let text = try arguments.string("text")
        try Task.checkCancellation()
        // A fix that can't be timed is still a fix: it's kept as one word, and the reason is passed on.
        var timings: [AlignedWord]?
        var problem: String?
        do {
            timings = try await FixTimer().timings(for: range, as: text, in: folder)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            problem = error.localizedDescription
        }
        try Task.checkCancellation()
        let (edit, fix) = try folder.fixWords(range, as: text, timings: timings, author: context.author, reason: "Fixed \(range) to “\(text)”")
        let ids = fix.words.count == 1 ? fix.words[0].id.description : "\(fix.words[0].id)…\(fix.words[fix.words.count - 1].id)"
        let message = fix.isTimed
            ? "\(range) now reads “\(text)”, as \(ids), timed against the audio."
            : "\(range) now reads “\(text)”, as \(ids). "
                + (problem.map { "It couldn't be timed (\($0)), so it cuts as one word." } ?? "It couldn't be matched to what was said, so it cuts as one word.")
        return try EditingOutput.after(message, edit: edit, folder: folder)
    }
}

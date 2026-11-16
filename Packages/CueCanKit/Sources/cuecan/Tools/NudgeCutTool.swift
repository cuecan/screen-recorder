import Foundation
import MCP
import ProjectKit
import RenderKit

struct NudgeCutTool: EditorTool {
    let name = "nudge_cut"
    let description = """
        Moves one edge of a clip by milliseconds or frames, for when a cut catches the start or the tail of a \
        word. There's no limit: clip edges are plain source times. Positive moves the edge later, negative \
        earlier, in the source's time. It says if the edge now lands inside a word. An edge the creator placed \
        by hand (placedByHand in get_edit) is theirs: move it only when they ask.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "clip_id": Schema.string("The clip, such as c_3, from get_edit."),
                "edge": Schema.oneOf(["start", "end"], "Which edge to move."),
                "milliseconds": Schema.number("How far to move it, in milliseconds."),
                "frames": Schema.number("Or how far in frames of the edited video, as the editor's frame step moves it. Give one of the two."),
            ],
            required: ["project", "clip_id", "edge"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let before = try folder.loadEdit()
        let clipID = try arguments.clipID("clip_id")
        guard let edge = ClipEdge(rawValue: try arguments.string("edge")) else {
            throw ToolError.invalidValue("edge", "use start or end.")
        }
        if arguments.has("milliseconds"), arguments.has("frames") { throw ToolError.invalidValue("frames", "give milliseconds or frames, not both.") }
        let seconds: Double
        if let milliseconds = try arguments.optionalDouble("milliseconds") {
            seconds = milliseconds / 1000
        } else if let frames = try arguments.optionalDouble("frames") {
            // Frames of the edit's own clock, as in the editor, so a faster clip moves farther in its source.
            let project = try folder.loadProject()
            let edit = try folder.loadEdit()
            let rate = Double(RenderFrameRate.standard(for: project, playing: edit.main.map(\.source)))
            let speed = edit.main.first { $0.id == clipID }?.speed.rate ?? 1
            seconds = frames / rate * speed
        } else {
            throw ToolError.missingArgument("milliseconds")
        }
        let (edit, result) = try context.change(folder, reason: "Nudged the \(edge.rawValue) of \(clipID) by \((seconds * 1000).formatted(.number.precision(.fractionLength(0)))) ms") { edit, transcripts in
            try edit.nudge(edge, of: clipID, by: seconds, transcripts: transcripts)
        }
        var message = "Moved the \(edge.rawValue) of \(clipID) to \(String(format: "%.3f", result.edgeTime)) s in the source."
        if !result.wordsAtEdge.isEmpty {
            message += " It now lands inside \(result.wordsAtEdge.map(\.description).joined(separator: ", ")): check it with preview_frames, or nudge back."
        }
        return try await EditingOutput.afterChecking(message, before: before, edit: edit, folder: folder)
    }
}

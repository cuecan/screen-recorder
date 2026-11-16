import Foundation
import MCP
import ProjectKit

/// Holds the picture on one frame while the camera and the voice play on (docs/decisions.md, 59).
struct FreezeScreenTool: EditorTool {
    let name = "freeze_screen"
    let description = """
        Holds the screen on one frame over a stretch of the edited timeline while the camera and the voice play \
        on, for when the creator clicked away too soon. With no screen, the camera holds. start_time and \
        end_time are seconds of the edited timeline; frame_time picks the frame to hold (the start if left \
        out). It's kept in source time, so it follows later cuts. remove with freeze_id takes one out, or \
        remove with a time range takes out every freeze there.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "start_time": Schema.number("Where the hold starts, in seconds of the edited timeline."),
                "end_time": Schema.number("Where it ends."),
                "frame_time": Schema.number("The timeline time of the frame to hold. The start if left out."),
                "freeze_id": Schema.string("A freeze to remove, such as f_4."),
                "remove": Schema.boolean("Take out freeze_id, or every freeze from start_time to end_time."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let request = try FreezeRequest(arguments)
        let folder = try context.folder(arguments)
        switch request {
        case .remove(let id):
            let (edit, _) = try context.change(folder, reason: "Removed \(id)") { edit, _ in try edit.removeFreeze(id) }
            return try EditingOutput.after("Removed \(id).", edit: edit, folder: folder)
        case .removeRange(let range):
            let (edit, count) = try context.change(folder, reason: "Removed freezes \(range.formatted)") { edit, _ in edit.removeFreezes(overlapping: range) }
            return try EditingOutput.after("Removed \(count) \(count == 1 ? "freeze" : "freezes").", edit: edit, folder: folder)
        case .create(let range, let frame):
            let (edit, made) = try context.change(folder, reason: "Froze the screen \(range.formatted)") { edit, _ in
                try edit.freeze(timeline: range, holdingFrameAt: frame)
            }
            return try EditingOutput.after("Froze the screen over \(range.formatted): \(made.map(\.id.description).joined(separator: ", ")). Check it with preview_frames.", edit: edit, folder: folder)
        }
    }
}

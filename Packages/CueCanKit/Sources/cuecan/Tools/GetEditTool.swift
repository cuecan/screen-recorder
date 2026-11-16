import Foundation
import MCP
import ProjectKit

struct GetEditTool: EditorTool {
    let name = "get_edit"
    let description = """
        The edit as it stands: each clip on the timeline with its id, the words it plays, where it lands, its \
        source time, its layout and look (one of each, drawn for the 16:9 video and the 9:16 Short alike), \
        its static screenTransform and cameraTransform overrides (centre and zoom; absent means the \
        take's framing), its speed, and edges the creator placed \
        by hand, and edges that sound runs right across, which may catch a word (soundAtEdges, with the nudge_cut that clears each); the overlays and freezes; the look every clip shares; the sound levels; word fixes; the project's \
        format; and the latest changes, yours and the creator's, numbered for undo.
        """
    var inputSchema: Value { Schema.object(["project": Schema.project], required: ["project"]) }
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let edit = try folder.loadEdit()
        let check = await EdgeCheck(after: edit, folder: folder)
        let summary = try ToolOutput.json(
            EditSummary(edit: edit, project: try folder.loadProject(), transcripts: try folder.loadTranscripts(), history: try folder.history.entries(),
                        edgeSounds: check.now)
        )
        return check.warning.map { ToolOutput(text: $0 + "\n\n" + summary.text) } ?? summary
    }
}

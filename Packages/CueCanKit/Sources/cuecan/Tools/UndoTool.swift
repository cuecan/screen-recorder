import Foundation
import MCP
import ProjectKit

struct UndoTool: EditorTool {
    let name = "undo"
    let description = """
        Puts the edit back as it was before the latest change, or before change number `change` and everything \
        after it (numbers are in get_edit's changes). Nothing is deleted: undone changes are kept in history/undone.
        """
    var inputSchema: Value {
        Schema.object(
            ["project": Schema.project, "change": Schema.number("Undo this change and every one after it. Leave out for the latest.")],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let edit = if let change = try arguments.optionalInt("change") { try folder.undo(through: change) } else { try folder.undo() }
        return try EditingOutput.after("Undone.", edit: edit, folder: folder)
    }
}

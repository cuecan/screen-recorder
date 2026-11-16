import Foundation
import MCP
import ProjectKit

struct ListProjectsTool: EditorTool {
    let name = "list_projects"
    let description = """
        Lists recent CueCan projects, newest change first: each one's folder, format, sources, and whether each \
        source is synced, transcribed and has its voice cleaned. Pass a project's folder to the other tools.
        """
    let inputSchema = Schema.object([:])
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let projects = context.library.projects()
        guard !projects.isEmpty else {
            return ToolOutput(text: "No projects yet. Record a take in the CueCan app first. New projects go in \(context.library.projectsFolder.path(percentEncoded: false)).")
        }
        return try .json(projects)
    }
}

import Foundation
import MCP

/// One tool, for the MCP server and the command line alike.
protocol EditorTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: Value { get }
    /// Reads only, so Claude can call it freely.
    var readOnly: Bool { get }
    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput
}

extension EditorTool {
    var readOnly: Bool { false }

    var mcpTool: Tool {
        Tool(
            name: name,
            description: description,
            inputSchema: inputSchema,
            annotations: .init(readOnlyHint: readOnly, destructiveHint: false, idempotentHint: readOnly, openWorldHint: false)
        )
    }
}

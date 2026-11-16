import Foundation
import MCP

/// `cuecan mcp`: the stdio MCP server Claude Code and Claude Desktop talk to (docs/design.md, "The MCP server").
enum MCPServer {
    static let version = "0.1.0"

    static let instructions = """
        CueCan for Mac edits a creator's videos by transcript. Every word and pause has an id (w_12, s_3); cut, keep \
        and add clips by those ids, never by quoting text, and the cuts snap to real pauses. Where words don't \
        help (between two words, a long wait on screen) cut, keep and split by exact time.
        A new recording starts with the whole take as one clip, so a good pass is list_projects, get_transcript, then \
        cut from it with cut, keep and remove_silences (add_clip adds more). Nothing is cut automatically: retakes, fillers and pauses are marked for you to decide. \
        Keep the last complete take of each line. get_screen_timeline shows what happened on screen, for waits to \
        cut, freeze_screen or set_speed. Look at your cuts with preview_frames before render. Every change can be \
        undone.
        The creator edits the same project in CueCan's editor: get_editor_state gives their playhead and \
        selection, so "cut here" works. Edges they placed by hand are theirs; your broad passes leave them alone.
        The app works with CueCan (cuecan.com), where a video's script is planned as beats.
        """

    static func run(context: ToolContext = ToolContext()) async throws {
        let server = Server(
            name: "cuecan-mac",
            version: version,
            title: "CueCan for Mac",
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolCatalog.all.map(\.mcpTool))
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            await call(parameters.name, arguments: parameters.arguments ?? [:], context: context)
        }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    /// Runs one tool. A failure comes back as an error result Claude can read, not a protocol error.
    static func call(_ name: String, arguments: [String: Value], context: ToolContext) async -> CallTool.Result {
        guard let tool = ToolCatalog.tool(named: name) else {
            return CallTool.Result(content: [.text(text: ToolError.unknownTool(name).localizedDescription, annotations: nil, _meta: nil)], isError: true)
        }
        do {
            let output = try await tool.run(ToolArguments(arguments), context: context)
            var content: [Tool.Content] = [.text(text: output.text, annotations: nil, _meta: nil)]
            content += output.images.map { .image(data: $0.data.base64EncodedString(), mimeType: $0.mimeType, annotations: nil, _meta: nil) }
            return CallTool.Result(content: content)
        } catch {
            return CallTool.Result(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
        }
    }
}

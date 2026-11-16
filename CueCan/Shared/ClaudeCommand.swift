import Foundation

/// How Claude is pointed at this copy of the app's MCP server, for Settings and the first-run setup.
enum ClaudeCommand {
    /// The `cuecan` CLI inside this copy of the app.
    static var cliPath: String {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/cuecan").path(percentEncoded: false)
    }

    /// The command that adds the server to Claude Code.
    static var claudeCode: String { "claude mcp add cuecan-mac -- \(cliPath) mcp" }

    /// The entry for Claude Desktop's config.
    static var desktopConfig: String {
        """
        {
          "mcpServers": {
            "cuecan-mac": { "command": "\(cliPath)", "args": ["mcp"] }
          }
        }
        """
    }
}

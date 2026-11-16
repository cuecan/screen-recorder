// The `cuecan` command-line tool, shipped at CueCan.app/Contents/Helpers/cuecan. `cuecan mcp` runs the MCP
// server Claude edits with; the same tools run as subcommands for the terminal and for scripts.
import Foundation

exit(await CuecanCommand.run(Array(CommandLine.arguments.dropFirst())))

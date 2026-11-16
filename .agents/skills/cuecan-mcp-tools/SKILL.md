---
name: cuecan-mcp-tools
description: Add or change a tool of CueCan's MCP server, or anything else the `cuecan` command-line helper does. Covers the tool protocol, the catalog, argument and schema helpers, how to write a tool's description and errors for an agent, the server's instructions, the machine-readable commands the app calls, and how tools are tested. Use when adding, renaming or changing an MCP tool, its arguments or its output, or a `cuecan` subcommand.
---

# The `cuecan` helper and its MCP tools

The helper is `Packages/CueCanKit/Sources/cuecan`. It's embedded in the app at `Contents/Helpers/cuecan`.

## One tool, three ways in

A tool is written once and runs as:

- an MCP tool, through `cuecan mcp` (stdio);
- a subcommand, `cuecan <tool> '{"project": "…"}'` or `cuecan <tool> --project … --start_id …`;
- an entry in `cuecan tools`, which lists them all.

Try one from the package folder:

```sh
swift run cuecan tools
swift run cuecan list_projects
```

## Adding a tool

1. **Put the logic in ProjectKit first,** as an operation on `Edit` with its own tests (the `cuecan-edit-model` skill). A tool is thin: read the arguments, call the operation, say what happened.
2. **Add `Tools/<Name>Tool.swift`,** a struct conforming to `EditorTool`:
   - `name`: snake_case, a verb first (`set_speed`, `remove_silences`).
   - `description`: written to the agent (below).
   - `inputSchema`: built with `Schema.object`, `.string`, `.number`, `.boolean`, `.oneOf`, `.list`. Use `Schema.project` for the project argument.
   - `readOnly`: true only if it changes nothing, so an agent can call it freely.
   - `run(_:context:)`: returns a `ToolOutput` with text, and images or an export result where there are any.
3. **Read arguments with `ToolArguments`:** `string`, `optionalDouble`, `wordID`, `clipID`, `range(from:to:)`, `timeRange()`. Each throws a readable error naming the argument. Use `reject(_:because:)` for arguments that can't be combined.
4. **Change the edit through `context.change(folder, reason:)`.** It saves under the project's lock with the right author and a snapshot, so the change shows in the history and `undo` can take it back.
5. **Register it** in `ToolCatalog.all`. The order there is the order tools are listed in.
6. **Test it** in `Tests/CuecanTests/ToolTests.swift`. Its `Workspace` makes a temporary library with one transcribed source and no media, enough for any tool that edits by id. Bad input belongs in `RequestValidationTests.swift`.

## Writing for an agent

- **The description is the documentation.** Say what the tool does, the units, which ids it takes, and what it won't do. Name the tool to use instead where there is one.
- **Errors are instructions.** A failure comes back as an error result the agent can read, not a protocol error. Throw a `ToolError` whose words say what to pass next.
- **Output is plain text** an agent can act on: what changed, new ids, and what to check.
- **Never make an agent quote text or guess a time.** Tools take word, silence and clip ids, and exact times only where words don't help.
- **`MCPServer.instructions`** is the short guide every connected agent gets. Change it when the way to work changes, and keep it short.

## Commands for the app

The app can't link the transcription code, so it runs the helper and reads JSON Lines:

```
cuecan --machine process <project>
cuecan --machine render …
cuecan --machine export_timeline …
cuecan --machine models [download]
cuecan --machine align --project … --start_id … --text …
```

The messages are `HelperMessage` in `ProjectKit/Helpers`, shared by both sides. Change a message there, and both ends with it. Progress is reported as it happens, and a failure is one final message with words a person can read.

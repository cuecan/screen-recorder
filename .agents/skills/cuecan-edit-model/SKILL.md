---
name: cuecan-edit-model
description: Change CueCan's project model in ProjectKit. Covers `project.json` and `edit.json`, format versions, where edit operations live, how a change is saved with its author and undo snapshot, the stable word, silence and clip ids, and how the app's editor and the MCP tools share one set of operations. Use when adding or changing a field in the edit or project, adding an edit operation, or when a project fails to open after a model change.
---

# The project model

Everything here is in `Packages/CueCanKit/Sources/ProjectKit`. It's pure Swift and thoroughly tested. Keep it that way: no AppKit, no AVFoundation, nothing that needs a window or a device.

## Where things are

| What | Where |
| --- | --- |
| The edit: a timeline of clips over one or more sources | `Edit/Edit.swift`, and its parts beside it |
| The project: its sources and their tracks | `Project/Project.swift` |
| Words and silences, each with a stable id | `Transcript/` |
| Every operation on an edit | `Editing/Edit+*.swift` (cutting, nudging, retiming, overlays, sound, words) |
| The project folder, its lock and its history | `Folder/` |
| What the editor shows and selects | `Editor/` |

## Format versions

Each file type carries its own version: `Edit.currentFormatVersion`, `Project.currentFormatVersion`, and the transcript, levels and screen-analysis types.

When a change alters what's written to disk:

1. Bump that type's version.
2. Change the type. Don't read old keys, default a field an older version didn't write, or fix up an old file on open. The formats can change freely during the beta.
3. Check that an older file still fails clearly. `ProjectFolder.loadProject()` and `loadEdit()` read the version first, so an older or newer file says so and never complains about a missing key.
4. Update the JSON round-trip tests (`ProjectKitTests/CodingTests.swift`) and any fixture that writes the type.
5. If an agent can see or set the field, update the MCP tool that carries it (the `cuecan-mcp-tools` skill).

Don't convert anyone's existing projects, even for a test. A check that needs a take uses one recorded with the current version.

## Saving a change

A change to the edit goes through one door:

```swift
try folder.updateEdit(author: .app, reason: "Cut a pause") { edit, transcripts in
    try edit.cut(…)
}
```

- It takes the folder's lock, reads the current files, runs the body, writes atomically, and snapshots the edit as it was into `history/`.
- **`author`** says who did it: `.app`, `.agent(name)`, `.commandLine(name)` or `.system(name)`. **`reason`** is what the history shows.
- The app and the `cuecan` helper can both have a project open. The lock keeps one from overwriting the other, and the app reloads when the edit changes on disk.
- Undo moves snapshots into `history/undone/`; it never deletes them.

Callers don't write `edit.json` themselves:

- **The app:** `EditorModel.change(_:_:)`, which saves as `.app`. Every gesture in the editor is one of the edit's operations.
- **The helper:** `ToolContext.change(_:reason:_:)`, which saves as the agent or the command line.

## One set of operations

An operation belongs on `Edit`, in `Editing/`, with tests. The editor's gesture and the MCP tool then both call it, so a person and an agent can do exactly the same things, and undo covers both. Don't put edit logic in a view or in a tool.

## Ids and cut points

- Every word and every silence has a stable id (`w_104`, `s_12`). Clips, sources and freezes have ids too. An agent cuts and keeps by a range of ids, never by quoting text.
- A range of ids becomes clip times at the nearest real pause (`CutPointSnapper`, `EditSnapper`), so a cut doesn't clip a word.
- Where words don't help, operations take exact times.
- An edge a person placed by hand is theirs (`startPlacedByHand`, `endPlacedByHand`). Broad passes such as removing silences skip any cut that would move one.

## Tests

`Tests/ProjectKitTests` has a file per area, with shared fixtures in `Fixtures.swift`. A new operation gets tests for the ordinary case, the edges of a clip, and what it refuses. In Swift Testing, call a mutating method into a `let` first and `#expect` on the result.

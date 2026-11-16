# CueCan for Mac

A free screen recorder and editor for macOS. It records the screen with a camera, or the camera alone, cleans the voice, transcribes on the Mac and times every word, and has its own editor. It exports MP4, SRT and an FCPXML timeline. It doesn't import footage.

A local MCP server (`cuecan mcp`) lets an agent such as Claude edit the same take by word id. That's an extra: the app does everything without it, so never describe it as needing an agent.

## Layout

- **`Packages/CueCanKit/`** is nearly all of the code, as a Swift package.
  - `ProjectKit`: the project on disk (`project.json`, `edit.json`), the edit and every operation on it, transcripts and captions. Pure Swift. It depends on nothing, and everything else depends on it.
  - `RecorderKit`: capture, the capture area, window snapping, access.
  - `AudioKit`: reading audio, levels, loudness, voice cleanup.
  - `TranscribeKit`: speech to text and word timing, on Core ML.
  - `RenderKit`: layout geometry, the preview, export, SRT and FCPXML.
  - `ProcessingKit`: what runs after a take is saved: clean, transcribe, time.
  - `UpdateKit`: updates, through Sparkle.
  - `cuecan`: the command-line helper and MCP server, embedded in the app.
- **`CueCan/`** is the SwiftUI app: views and app wiring only.
- **`CueCanTests/`** holds unit tests that have to run inside the app. **`scripts/`** has the release script, and **`.github/workflows/`** the workflows that test pull requests and build releases.

## Build and test

Xcode 27 and Swift 6.4, on an Apple silicon Mac.

```sh
# The package: most work happens here
cd Packages/CueCanKit && swift build && swift test

# The app, signed ad hoc, which needs no signing team: enough to check that it compiles
xcodebuild -project CueCan.xcodeproj -scheme CueCan -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

# The app's own unit tests, signed the same way as the app
xcodebuild -project CueCan.xcodeproj -scheme CueCan -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -only-testing:CueCanTests test
```

To run the app and keep its permissions between builds, set your own signing team in Xcode first. The `cuecan-run-app` skill says why.

## Rules

1. **Logic goes in the package, views in the app.** Anything that can run without a window lives in `CueCanKit`, with tests. The app can't import `TranscribeKit` or `ProcessingKit`; it runs the embedded `cuecan` helper for that work.
2. **Everything stays on the Mac.** No analytics, no crash reporting, and no new network request. The app makes three kinds today: the update feed, a line of news, and the speech models' download.
3. **Never invent a number, a result or a measurement,** in code, tests, comments or copy. Mark what isn't known: `VERIFY`, `TEST NEEDED`, or `AUTHOR'S TAKE NEEDED` for a judgement by eye or ear.
4. **The formats can change during the beta.** Bump the format version and let an older project fail to open with a clear message. No migrations, and no reading old keys.
5. **Test everything that runs without hardware,** in Swift Testing (`import Testing`, `@Test`, `#expect`). Capture needs the signed app and real devices.
6. **Apple's frameworks first.** Check the current documentation before relying on remembered behaviour: ScreenCaptureKit, AVFoundation and Speech have changed across recent macOS releases. Anything newer than macOS 26 goes behind `if #available`.
7. **Dependencies are few and pinned on purpose.** Raise it before adding or upgrading one.
8. **Style:** Swift API Design Guidelines and descriptive names; `///` on public types and anything non-obvious; no force unwraps outside tests. Swift 6 language mode. The app target defaults to the main actor, and a file there imports the module of every member it uses.
9. **Words a person sees:** a title, and one short line at most. An error says what went wrong in words a creator understands.
10. **Comments say why.** No names and no dates, and a feature is described in its own terms, never by naming another product.
11. **A comment that cites a numbered decision marks a deliberate choice.** The decision records aren't in this repository, so raise it before changing what the comment covers. `docs/architecture.md` has the modules and where code goes.

## Skills

Procedures live in `.agents/skills/` (linked from `.claude/skills/`), so they cost nothing until they're needed. Read the one that matches before you start.

| Skill | Read it when you |
| --- | --- |
| `cuecan-run-app` | run the app, check something on screen, reset access or first run, or set a debug setting |
| `cuecan-xcode-project` | touch the Xcode project, a target's settings, the Info.plist, signing or the embedded helper |
| `cuecan-edit-model` | change `edit.json` or `project.json`, or add an edit operation |
| `cuecan-mcp-tools` | add or change an MCP tool, or anything the `cuecan` command line does |
| `cuecan-speech` | change voice cleanup, transcription, word timing or cut points |
| `cuecan-takes` | look at a project folder on disk, or work out what went wrong with a take or an export |
| `cuecan-ui` | build or change a screen, a panel, a menu, or any text a person reads |
| `cuecan-release` | build a release, or change updates, the news line or the beta's time limit |

## When you finish

Say what changed, what you ran, what you checked by hand, and what is still unchecked. Don't say a capture, a drag or a key works unless a person saw it: automation can't do those here.

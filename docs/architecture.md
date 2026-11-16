# Architecture

One Swift package does the work. The app and the MCP server are two thin front ends on it, and both read and write the same project folder. Neither needs the other running: an agent can edit through the `cuecan` CLI with the app closed, and the app watches `edit.json` and updates its preview when the agent changes it.

```
        You                                                 An agent (optional)
  record, edit, export                                     talks MCP over stdio
          |                                                      |
          v                                                      v
  +-------------------------------+            +-------------------------------+
  | CueCan.app  (SwiftUI, menu bar)|            | cuecan  (CLI; `cuecan mcp`)    |
  | recorder, editor, preview,     |            | cuts, layouts, sound, frames,  |
  | export                         |            | render, SRT, FCPXML            |
  +-------------------------------+            +-------------------------------+
          |                                                      |
          v                                                      v
  +---------------------------- CueCanKit (Packages/CueCanKit) ----------------------------+
  |  RecorderKit                         AudioKit                 ProcessingKit             |
  |  ScreenCaptureKit, AVFoundation      cleanup, DSP, loudness   after-recording jobs      |
  |                                                                                         |
  |  TranscribeKit            ProjectKit                 RenderKit                          |
  |  transcribe, time words   project.json, edit.json    AVComposition, compositor          |
  |  word ids, real silences  snapshots, undo            preview, export, SRT, FCPXML       |
  +-----------------------------------------------------------------------------------------+
                                         |  reads and writes
                                         v
  Project folder: project.json · recordings/ · proxies/ · audio/ · transcripts/ · edit.json · history/ · exports/
  The recordings are never modified.
```

## Modules

| Module | Owns | Depends on |
| --- | --- | --- |
| `ProjectKit` | The project folder, `project.json`, `edit.json`, transcript types with word and silence ids, `history/` snapshots and undo | nothing |
| `RecorderKit` | Screen, camera, mic and system-audio capture to separate files on the host clock; the live mic meter; capture areas and window snapping | ProjectKit |
| `AudioKit` | The three audio stages after recording: Cleanup (Off or Natural) and Voice (Clear, Broadcast), each with an amount, then Loudness on the final mix | ProjectKit |
| `TranscribeKit` | Parakeet (FluidAudio, Core ML) and Apple's SpeechAnalyzer, each timing its own words; vocabulary boosting; stable ids; real silences for cut points; retake and filler marks; forced alignment of a fix (`ForcedAligner`, `CTCWordAligner`) | ProjectKit, AudioKit, FluidAudio |
| `RenderKit` | `edit.json` to `AVComposition`, the custom compositor (layouts, crops, overlays, the look), freezes and speed, preview of every output side by side, stills, export, SRT and plain text, FCPXML (`FCPXMLWriter`). Export takes the mastering as a function, so it doesn't depend on AudioKit | ProjectKit |
| `ProcessingKit` | What runs on its own after a recording: Cleanup and Voice into `audio/`, transcription with SpeechAnalyzer's second reading, vocabulary boosting, reading the screen (`ScreenReader`); timing a fix to the transcript (`FixTimer`, run by `set_word_text` and `cuecan --machine align`); and the mic cleaned without Voice for the export to another editor | ProjectKit, AudioKit, TranscribeKit |
| `cuecan` | The CLI: `cuecan mcp` runs the MCP server, and the same tools work as subcommands. Ships at `CueCan.app/Contents/Helpers/cuecan` | everything except RecorderKit |

The dependency arrows only point down into `ProjectKit`. Keep it that way: if two feature modules need to share something, it belongs in `ProjectKit` or in a new small module, not in a dependency between siblings.

`ProcessingKit` sits on top of AudioKit and TranscribeKit, like the CLI. The app doesn't link it: it runs `cuecan process`.

`cuecan` deliberately doesn't link `RecorderKit`. It never records, and leaving capture out keeps the binary that an agent launches free of camera, mic and screen code.

## Repository layout

```
CueCan.xcodeproj/             Xcode 27 text project format (project.xcproj); see the `cuecan-xcode-project` skill before editing
CueCan/                       the app target: a thin SwiftUI shell (synchronized folder: new files are picked up)
CueCanTests/  CueCanUITests/  app-level tests (Swift Testing / XCUITest)
Packages/CueCanKit/           almost all code and its tests
Config/                       the app's Info.plist
scripts/                      the release script
.github/workflows/            the workflows that test pull requests and build releases
docs/                         this file, and the README's pictures
```

## Where code goes

- **Logic goes in the package.** Anything that can run without a window (models, capture pipelines, DSP, transcription, composition, MCP tools) lives in `CueCanKit`, where `swift build` and `swift test` run it from a terminal.
- **The app target holds views and app wiring only:** scenes, SwiftUI views, permission prompts, the menu bar and panels, and glue that calls into the package.
- **Capture is tested through the app.** Camera, mic and screen permission prompts belong to the signed app bundle, so a test that really captures runs in the app or a UI test, not in `swift test`.

## Saving a project

`ProjectFolder` holds the project's lock for every change, and while it creates a project. The lock is `.lock` in the project folder, shared with every process that opens the project, such as the app and the `cuecan` CLI.

- **A change that spans several files is saved in three steps:**
  1. a record of the whole change goes in `.pending-mutation.json`;
  2. each file is written;
  3. the record is removed.
- **Such changes are:**
  - an edit, with its history snapshot;
  - an undo, with the snapshots it moves to `history/undone/`;
  - a transcript, with the word and silence ids it takes from `project.json`.
- **If saving is interrupted, the record stays.** Whoever opens the project or takes the lock next finishes the change first. It uses the same history number and the same ids, so finishing a change twice does no harm.
  - A save can report an error and still be finished on the next open, so reload before trying again.
- **If a change can't be finished, nothing more can be saved.** The error (`ProjectFolderError.unfinishedChange`) says so and names the file.
- **Opening a project with nothing pending only reads it,** so a project on a read-only disk still opens.
- **It guards against a process stopping partway through a save.** It doesn't guard against a damaged disk, or promise that a save survives a power cut.
- **A read sees either the old file or the new one,** because each file is replaced in one step. To see several files as they were at one moment, read them under `withLock`.
- **The formats are the same with or without the record:** `project.json`, `edit.json`, transcripts and history.

## Lifecycles and shared operations

- **Recording:** `RecordingSession` explicitly owns prepared, recording, paused, failed, finishing, finished and discarded states. The first failure freezes the capture clock immediately, before the UI handles its callback, and survives finalization for the app's alert. Concurrent Stop calls share one finalization result. `RecordingFinalizer` closes every track, then probes each candidate independently, retaining readable fragments including a failed mic's WAV; an unreadable track cannot prevent the others from being saved. It then cuts the files to the time they all cover (`TakeSpan`, `TrackTrimmer`), all of them or none. The session shares one encoded-track registration list across callbacks, finalization and diagnostics. `TrackWriter` owns its writer and input together in its lifecycle state; only an explicit discard cancels and deletes unfinished output. Detaching a `BufferSink` waits for its current callback to finish.
- **Device readiness:** `DeviceReadiness` separates saved selection from permission, startup, ready and unavailable states. The app enables capture only after `CameraCapture.use` / `MicCapture.use` succeeds. Startup tokens reject completions from a closed or replaced setup.
- **Background work:** `ProcessingQueue` reserves a single worker and coalesces changes during processing into one follow-up pass. `ThumbnailQueue` reserves before starting asynchronous work and checks a request identity and revision before publishing. Forgetting a project invalidates its pending result.
- **Helper messages:** the bundled CLI's `--machine` mode emits JSON Lines using `HelperMessage`: zero or more `ProcessingProgress` events, then one `ProcessingReport`, `ExportResult` or failure. `CommandRunner` drains both pipes. The app never interprets human output as filenames or errors. Partial cleanup failures remain export warnings shown in Background Tasks.
- **Export snapshots:** `RenderInputs.load` captures project, edit, transcript, spellings and resolved primary-audio URLs under the project lock. `ExportPlan` adds the destination and typed finished-video or handoff choices; it can be serialized to the helper without reloading the edit. `FinishedExporter` owns video/transcript orchestration and naming for app and CLI. Cleanup outputs use unique filenames so later processing cannot overwrite an in-flight export's audio; recording a new one removes the source's older files except those a record names and the one it just replaced. Handoff cleanup uses the captured settings and its own sidecar. `AlignedCleanup` shares cleanup, resampling and sample alignment between preview and handoff processing.
- **Trim feedback:** `ProjectKit.TrimPreviewPlan` stages the existing edge operation in memory and identifies the output frames either side. `RenderKit.TrimPreviewSession` captures inputs once per gesture and renders low-resolution stills through the export compositor. The app owns presentation, one newest-target decoder queue, cancellation and a twelve-pair image cache; it never saves the staged edit. Export mastering accepts cancellation checkpoints through the loudness meter, gain and limiter without changing their calculations.
- **Sound and the trim loupe:** mix-only updates publish the new edit and timeline together while keeping the player item, so level-line drawing and hit testing match the playing mix. The loupe's presentation has hidden, loading, ready and failed states, carrying its plan, previous pictures and failure where applicable; a decoder cancellation independent of gesture cancellation cannot leave a permanent loading state. Its cache keys use `ClipEdge` directly. Keyboard feedback for an already decoded target keeps the brief dismissal interval.
- **Calibration and captions:** `RecorderKit.SyncCalibrationProgress` owns ready, starting, listening, measured and failed states and rejects updates from cancelled or superseded runs. The app's `SyncCalibrationCapture` boundary keeps device startup, taps and shutdown together; a retry waits for the cancelled run's cleanup. Caption lead is clipped to the owning clip's timeline range, and disabled clips have no caption instructions. Layout cache keys carry the caption track's unique identity, exact panel size and full placement, including alignment. Measured word-onset levels are picture inputs, so changing them requires a composition rebuild rather than a mix-only update. Enabling loudness audition on an empty or failed preview settles immediately into the matching result.
- **Editor interactions:** `EditTimeline`, `PlayedWord`, `TimelineLane`, `TimelineTool` and `TimelineInteraction` live in `ProjectKit`. The editor draws and applies typed interaction actions; hit testing, drag previews, snapping and gesture completion are pure package logic. A changed edit revision cancels an active gesture until mouse-up. SRT exports and the words written in the audio lane use the same played-word projection (`PlayedWord`); SRT exports omit fillers and empty corrected words while the editor keeps them selectable.
- **Editor loading:** a selected folder opens once off the main thread, with explicit failure/retry state. Preview failures remember the attempted revision rather than rebuilding unchanged missing media indefinitely. A background poster is optional and does not gate the player or editing controls; it reads independent composition objects through the async asset-reader provider, with cancellation and a deadline. `TimelineZoom` shares the slider limits and fit margins between the UI and package tests.
- **Timeline responsiveness:** `TimelineViewport` owns visible-range, anchored-zoom and reveal geometry. The app keeps static timeline content separate from the moving guides and transport clock, culls drawing to the viewport and caches `PlayedWord`/`EditSnapper` projections when inputs reload. `ClipPicking` owns Shift-range and Command-toggle intent. `Edit.edgeRange` bounds pointer feedback without changing the exact edit tool's validation. `PreviewSeeking` allows one seek in flight plus the latest target; replacement tokens reject stale completions.
- **Background work and exports:** `AppModel` owns `ExportCenter`, whose pure `ProjectKit.ExportQueue` reserves one renderer at a time and retains per-export `ExportJob` results after setup closes. `ExportPlan` carries the captured inputs, choices, destination and reviewed filename through the helper snapshot. `ExportAudioSnapshot` retains the captured cleaned audio with hard links in a hidden `.export-inputs-UUID` directory on the project's volume, so repeated cleanup cannot delete a waiting export's audio. The app releases each job's links on cancellation or completion. The app stages outputs, then `RenderKit.ExportPublication` moves each completed group into place without deleting existing final files; a failed group moves back. CLI export defaults and replacement behavior stay as documented for those tools. The shared Background Tasks popover reads exports, processing and visible-editor preview preparation; unknown-length work is indeterminate, while file progress comes from the encoder.
- **Opening, preview and camera states:** `ProjectOpenState` makes opening, opened and failed mutually exclusive. `PreviewLoad` owns loading, seeking, ready, empty and failed states, the failure message and the request identity used by both seek and poster completions. A replacement player remains preparing until its seek completes, so a temporary pause is not mistaken for playback ending. Failure to copy an optional poster composition leaves the player available. `CameraFrameWatch` owns waiting, delivering, restarting and failed states; restart completions carry tokens and start the next waiting period only after capture restarts. `LayoutChoice` owns available editor buttons and size selection; the output-specific edit operation preserves the other output and stores Automatic only for each clip's matching recorded preset. Renderer, inspector, timeline and still descriptions share output layout resolution.
- **Correction and seek lifecycles:** `TranscriptFixing` owns idle and aligning states with unique request identities. Replacing a pending correction, Undo/Redo or closing the editor invalidates its completion before it can save; the CLI also checks cancellation before saving an untimed fallback. The inline text field owns its range and field together in a reading/editing state. `PreviewSeeking` holds the in-flight request and optional waiting target in one seeking state. The CTC aligner caches its spotter and tokenizer together only after both load successfully.
- **Inspector and static framing:** `ProjectKit.PictureTransform` and `Edit.setTransform` own sparse per-clip screen/camera overrides and their bounds; copying/splitting clips preserves them. `LayoutGeometry` resolves the effective take default or clip override for the app, renderer and CLI. `BuiltComposition.reframed` reuses media tracks and redraws instructions when `RenderInputs.differsOnlyInFraming` permits it. The app's `FramingAudition` coalesces independent poster reads during a gesture; a changed release persists one edit, while an unchanged release restores the persisted picture without changing mixed values or clearing feedback. `FrameReadCancellation` keeps native teardown outside preparation and extraction. `FrameReadTask` bounds the caller's wait and the number of unfinished native workers; a native read itself may remain blocked until the OS returns. `PanelPlayerView` gates visibility by the exact ready item as well as layer readiness; `FrameHold` keeps the last useful picture through rapid replacements. `EditorSnapshot` prepares render inputs, history and redo availability away from the UI thread. Undo decodes only the snapshots being undone. Inspector sections/rows/number fields are UI components, not edit state. Audio amount buttons commit discrete choices; a no-op neither reloads the preview nor starts source processing.
- **Correction inputs and references:** the two-argument `ProjectFolder.updateEdit` supplies the current corrected transcript under the same mutation lock, shared by app and tools. `FixAlignmentContext` owns the context words and matching source/file audio ranges; source time zero for alignment follows the actual mic window, including a late mic start. Retiring an overlay's word or silence anchor preserves its existing source-time placement. Alternatives and retakes overlapping replaced words are discarded, including replacements inside their endpoints. Pending correction text appears once per clip occurrence across paragraph breaks.
- **Export delivery:** `ExportCenter` keeps each plan with its retained audio. Publication accepts callbacks only for the running attempt's incomplete items; Stop and publication failure close that gate before cancelling the renderer. A late callback from an uncancelled helper cannot publish files after Stop.
- **Tool arguments:** `EditTarget`, `OverlayRequest`, `SplitRequest` and `FreezeRequest` decode mutually exclusive request shapes before mutation. Tool schemas don't express those alternatives: Claude's API rejects `oneOf`, `anyOf` and `allOf` at the top of a tool's schema, so the descriptions say which arguments go together and the tools check them. Numeric decoding rejects non-finite values and uses exact, range-checked conversion for integers.
- **History:** `EditAuthor` stores a role (`app`, `agent`, `commandLine`, `system`) and a name where appropriate. A project in an older format is rejected before journal recovery, without migration. Edit, undo and redo all use the same `ProjectMutation.history` recovery path, including the redo stack.

Package tests cover lifecycle failures, queue reruns and stale completions, helper subprocess results and warnings, export audio snapshots, conflicting requests without mutation, numeric bounds, pointer transitions, shared word timing, and interrupted history recovery. Real-device capture, long-recording sync, editor gestures in the running app, and importing FCPXML into another editor still need the existing manual checks; synthetic fixtures do not establish recording or audio quality.

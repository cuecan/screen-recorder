---
name: cuecan-takes
description: Read a CueCan project folder on disk and work out what went wrong with a take, an edit or an export. Covers where projects live, what each file and folder holds, how to inspect them with the `cuecan` helper and standard tools, how two processes share a project, and what to leave alone. Use when debugging a recording, a transcript, a preview or an export, or when a task needs a real take to check against.
---

# Looking at a take on disk

## Where projects are

Each recording is a plain folder in `~/Movies/CueCan`, named with its day and title.

```
<day> <title>/
  project.json        the sources and their tracks
  edit.json           the edit: a timeline of clips
  editor-state.json   the editor's playhead and selection
  recordings/         what was recorded, one folder per take
    screen.mov  camera.mov  mic.wav  system.m4a
  transcripts/        one per source: words and silences with ids and times
  audio/              the cleaned voice per mic source; can be made again
  proxies/            small copies for the preview; can be made again
  screen/             what happened on screen, and its text
  history/            edit.json as it was before every change
  exports/
```

- A take's tracks are separate files on one clock. They're cut when the take is saved, so each starts at zero and they end together.
- The mic is recorded raw, as 48 kHz mono. Cleaning writes a new file into `audio/` and never touches the recording.

## Reading a project

Use the helper before opening JSON by hand. From `Packages/CueCanKit`:

```sh
swift run cuecan list_projects
swift run cuecan get_edit --project "<path, id or title>"
swift run cuecan get_transcript --project "<path, id or title>"
swift run cuecan tools
```

For the media itself:

```sh
afinfo recordings/<take>/mic.wav
mdls -name kMDItemDurationSeconds recordings/<take>/screen.mov
```

If `ffprobe` is installed, it shows each stream's start and length:

```sh
ffprobe -v error -show_entries stream=codec_type,start_time,duration,r_frame_rate -of compact <file>
```

To see a frame of the edit at a time, use the `preview_frames` tool. `render` writes the finished video and `export_timeline` the timeline for another editor, both into `exports/`.

## What to check first

| Symptom | Look at |
| --- | --- |
| The project won't open | The `formatVersion` in `project.json` and `edit.json`. An older or newer one fails on purpose, with a message that says which. |
| A cut clips a word | The word's times in the transcript against the audio, then the silences around it |
| Picture and sound drift | Each track's start and length, which should match |
| An edit vanished | `history/`, in order. `cuecan undo` steps back; undone snapshots move to `history/undone/` |
| The cleaned voice is stale or missing | `audio/` holds nothing original: delete a file there and `cuecan process` makes it again |

## Two processes, one project

The app and the helper can have the same project open. Every write takes the folder's lock, reads the current files, changes them and writes them back in one step, and the app reloads when `edit.json` changes. So change a project through the helper or `ProjectFolder`, never by writing its JSON yourself.

## What to leave alone

- **A person's real recordings.** Work on a copy: Duplicate in the app's sidebar makes one with its own edit over the same recordings. Tests use a temporary library, never `~/Movies/CueCan`.
- **Old projects.** Don't convert one to a new format, even for a test. Record a new take with the current build.
- **Temporary files.** A test or a check that writes media, exports or a library cleans up after itself, so nothing of it shows up in the Projects window.

## What a file can't tell you

Lip sync as it looks, a camera that stalled, and how a cut sounds need a person. Say what you measured, and what still needs eyes or ears (`TEST NEEDED`).

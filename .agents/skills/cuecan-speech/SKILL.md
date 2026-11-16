---
name: cuecan-speech
description: Change how CueCan cleans the voice, transcribes, times words or finds cut points, and measure whether a change is better. Covers what runs after a take is saved, the speech models and where they download from, the pinned dependencies, how to check a change, and the rules for reporting audio and transcription results. Use when touching AudioKit, TranscribeKit or ProcessingKit, a speech model or its download, or when asked to compare engines or settings.
---

# Voice, transcription and word timing

## What runs after a take is saved

`ProcessingKit.SourceProcessor` does it, and the app runs it as `cuecan process <project>`. For each source that needs it:

1. **Transcribe** the main audio with Parakeet TDT v3 (FluidAudio, on Core ML).
2. **Place each word's start** with the timing model (`TranscribeKit.WordTimer`, then `WordRetimer`). If the model can't be downloaded, loaded or run, the transcript is still written, with Parakeet's own times.
3. **Fit the words to the audio** (`WordFitter`): real silences are measured, and no word sits inside one.
4. **Attach a second reading** from Apple's SpeechAnalyzer where it differs, as alternatives for spelling.
5. **Apply the project's vocabulary** with Parakeet CTC 110M, which also times a corrected word.
6. **Clean the voice** into `audio/` with the take's Cleanup and Voice settings. The recording itself is never changed.

Cut points depend on steps 2 and 3. A change there moves every cut an agent or a person makes by word.

## The models

Three downloads, about 960 MB in all. Check or fetch them with the helper:

```sh
swift run cuecan models
swift run cuecan models download
```

- **Transcription and vocabulary** come through FluidAudio, into its own cache.
- **The timing model** is CueCan's own download (`TranscribeKit.TimingModelDownload`):
  - It fetches a published Core ML model from Hugging Face at one pinned revision, and checks each file's hash.
  - It patches the model's description in place so the timing head returns its per-frame probabilities, checks the result's hash, and compiles it on the Mac.
  - It installs to `~/Library/Application Support/CueCan/Models/`.
  - `scripts/models/timing-model-patch.py` remakes the patch if the pinned revision ever moves. It needs Python 3.13 and Core ML tools.
- Once the models are there, everything works with no internet. Keep it so.

## Dependencies here are pinned on purpose

- **FluidAudio is pinned to one exact version,** with only its `NemoTextProcessing` trait on, because its speech-to-text code doesn't link without it. Don't move the version as a side effect of other work.
- **MLX and its speech packages were removed.** Raise it before bringing any back.
- **Loudness** is `AudioKit.LoudnessMeter`, a pure-Swift BS.1770 meter tested against EBU Tech 3341.

## Checking a change

There's no comparison harness in this repository. To check a change:

- Run the package's tests.
- Process a real take again and listen to it and read its transcript: `swift run cuecan process <project>`.

## Rules for results

- **A person judges sound, by ear.** Don't name a winner. Report what was measured and leave the verdict open (`AUTHOR'S TAKE NEEDED`).
- **Recordings are real.** Synthetic speech is fine for checking that the plumbing runs, and for measuring word timing against the synthesizer's own word times. It never shows how something sounds.
- **Never invent a number.** Every figure in a comment, a test or a report was measured in a run you can name.
- **Say what the measurement was on:** how many clips, how long, real or synthetic, one voice or several. A result on two short clips is a result on two short clips.

## Tests

- What can run without a model or a device is tested: silence detection on synthetic audio, fitting, the tokenizer, alignment plans, loudness.
- A few checks are off unless asked for, because they download or need a file:

| Environment variable | What it turns on |
| --- | --- |
| `CUECAN_MODELS_DOWNLOAD_CHECK` | Really downloads the speech models |
| `CUECAN_ALIGN_AUDIO` | Aligns a recording you name |
| `CUECAN_BENCH` | Caption drawing performance |

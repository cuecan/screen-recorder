---
name: cuecan-xcode-project
description: Change CueCan's Xcode project safely. Covers the text-format project file and its formatter, the target settings that were chosen on purpose, the Info.plist, entitlements and signing, which package products the app links, and how the `cuecan` helper gets into the app bundle. Use before editing anything in `CueCan.xcodeproj` or `Config/`, adding a target or package product, or when the app fails to link or the helper is missing from the bundle.
---

# The Xcode project

## You rarely need to edit it

`CueCan/`, `CueCanTests/` and `CueCanUITests/` are synchronized folders: a new file in one is picked up with no project change. Most work is in `Packages/CueCanKit`, which the project doesn't describe at all.

## Settings to keep

The app target was set up on purpose.

- **Platform:** macOS only, deployment target 26.0, `ARCHS = arm64`.
- **Signing:** App Sandbox off. Hardened Runtime on, with the camera and audio-input entitlements (`ENABLE_RESOURCE_ACCESS_CAMERA`, `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT`). An ad-hoc build turns the hardened runtime off and says so in the build log; a Developer ID build has it.
- **Info.plist:** generated, then merged with `Config/CueCan-Info.plist` (`INFOPLIST_FILE`).
  - `LSUIElement = YES` and the camera and microphone usage descriptions are `INFOPLIST_KEY_*` build settings.
  - `NSScreenCaptureUsageDescription` is in the file, because Xcode ignores an `INFOPLIST_KEY_` setting for that key.
  - The file also holds the update feed's address and key, and `CueCanBuiltOn`. Build settings expand in it as `$(NAME)`, and one that isn't set becomes an empty string.
- **Swift:** language mode 6. The app target defaults to the main actor, with approachable concurrency. A file must import the module that defines each member it uses, or the build fails with "not available due to missing import of defining module".
- **The team in the project is the maintainer's,** with automatic signing. Use your own locally and leave it out of your change. The test targets are signed the same way as the app, or their bundles won't load.

## Editing the project file

The project is in Xcode 27's text format, `CueCan.xcodeproj/project.xcproj`, a JSON-like file. It isn't the old `project.pbxproj`.

After any edit, run the formatter, then read the diff:

```sh
xcrun xcprojformatter --update CueCan.xcodeproj
```

It validates the file and rewrites it in canonical form. It reports a bad key or value precisely, but it silently drops keys it doesn't know.

Keys confirmed to work:

- **A local package,** at the top level: `"packages": [ { "kind": "local", "path": "Packages/CueCanKit" } ]`.
- **A package product as a target dependency:** `{ "kind": "package", "package": "CueCanKit", "product-name": "RecorderKit" }`. This only builds it.
- **Linking a package product,** on the target: `"package-product-members": [ { "package": "CueCanKit", "product-name": "ProjectKit", "build-phase": { "build-phase": "frameworks" } } ]`. Without this the product isn't linked.
- **A run-script phase:** `{ "kind": "script", "name": "…", "input-paths": [ … ], "output-paths": [ … ], "shell": "/bin/sh", "script": "…" }`.
- **A copy phase's destination,** as Xcode writes it: `{ "kind": "copy", "name": "…", "bundle-base-path": "executables-directory" }`.

Not worked out: putting a file into a copy phase. `target-membership` takes a target-relative phase reference, and no spelling of it resolved.

## What the app links

- The app links `ProjectKit`, `RecorderKit`, `AudioKit`, `RenderKit` and `UpdateKit`.
- It can't import `TranscribeKit` or `ProcessingKit`. They bring in FluidAudio, and Xcode's module scan can't find FluidAudio's C modules. The app runs the embedded helper for that work (`cuecan process`, `cuecan --machine …`).

## How the `cuecan` helper gets into the app

Xcode can't add a package's executable to a Copy Files phase, so it's done in two parts.

1. The app target depends on the package's `cuecan` product, so Xcode builds it into `BUILT_PRODUCTS_DIR`.
2. The "Embed cuecan CLI" script phase runs `scripts/embed-cuecan-cli.sh`, which copies it to `Contents/Helpers/cuecan` and signs it with the app's identity and the hardened runtime, as `com.jelled.CueCan.cuecan`.

Things that will break it:

- **Moving it to `Contents/MacOS`.** It would collide with the app's own `CueCan` executable on a case-insensitive disk.
- **Dropping the phase's declared inputs and outputs.** They're what lets it run with user script sandboxing on. In an archive the helper is built into `UNINSTALLED_PRODUCTS_DIR`, so the phase declares that path as an input too.
- **Signing in place.** The sandbox lets the script write only its declared outputs, and `codesign` and `ditto` both write a temporary file beside their target. The script signs a copy in a temporary folder, then copies it in with `cp`.

Check it after a build:

```sh
codesign -dv <build products>/CueCan.app/Contents/Helpers/cuecan
```

---
name: cuecan-run-app
description: Run CueCan for Mac and check a change in the running app. Covers which copy to launch, signing and macOS permissions, resetting access and the first-run setup, debug-only settings, the console, Xcode's agent tools, and what automation can't check. Use when asked to run, launch, screenshot or verify the app, or when a permission prompt, the first run or a debug setting is involved.
---

# Running CueCan and checking it on screen

## Run one copy: the one Xcode builds

- CueCan is a menu bar app (`LSUIElement`). It has a Dock icon only while its Projects window is open.
- macOS ties camera, microphone, Screen Recording and Accessibility access to the app's bundle id and signing team, not to its path.
  - Signed with a team, the app keeps its access across rebuilds.
  - Signed ad hoc, every build is a new app to macOS, which asks for everything again. Ad hoc is only for checking that it compiles.
- So before running it, choose your own team in Xcode (the CueCan target, Signing & Capabilities). Leave that change out of what you commit.
- A second copy somewhere else is a different app to macOS: its own permissions, and a second menu bar icon fighting over the global shortcuts.
- Before checking anything on screen, make sure one copy is running:

```sh
pgrep -fl "MacOS/CueCan"
```

## Access and the first run

- To be asked for every permission again:

```sh
tccutil reset All com.jelled.CueCan
```

- A first launch opens the setup window in place of Projects. It comes back when the `accessSetupDone` setting is removed (below). Settings › Recording › Access › Review… opens it at any time.

## Settings for testing

Set these from Xcode's debugger or from Terminal.app. A sandboxed agent shell can write preferences somewhere the app doesn't read; if `defaults write` seems to do nothing, that's why.

```sh
defaults write com.jelled.CueCan betaBuiltOn 2026-01-01
defaults delete com.jelled.CueCan accessSetupDone
```

In Xcode's debugger, pause, set and continue:

```
process interrupt
expression -l objc -- (void)[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"VisibleToScreenshots"]
continue
```

| Key | Type | What it does |
| --- | --- | --- |
| `VisibleToScreenshots` | Bool, Debug builds | The overlay panels are left out of screen capture, so a screenshot can't see them. This lets them be seen. It applies to panels made after it's set: set it before opening the setup bar. |
| `betaBuiltOn` | String, Debug builds | A build day in the form `2026-01-01`. A day more than 90 days back shows what an expired beta does. It's read each time a recording starts, so no relaunch is needed. |
| `accessSetupDone` | Bool | Remove it to get the first-run setup back. |

## The console

- `print`, `NSLog` and `Logger` all reach Xcode's console. CueCan logs under the subsystem `com.jelled.CueCan`, in the categories `recording` and `snapping`:

```sh
log stream --level debug --predicate 'subsystem == "com.jelled.CueCan"'
```

- Expect noise from the camera (CoreMediaIO, Center Stage), video effects, Core ML and "ClientDonation". None of it is CueCan's.

## Tests that run in the app

- `CueCanTests` holds unit tests for code that has to live in the app. They run with the app as their host.
- `CueCanUITests` has only the template's launch tests. They show that the app launches and nothing more.
- A test bundle loads only if it's signed the same way as the app: both with your team, or both ad hoc.
- The package's tests don't need the app: `swift test` in `Packages/CueCanKit`.

## With Xcode's agent tools

If you have Xcode's own tools (`BuildProject`, `RunProject` and the rest):

- **Open the project first,** by absolute path, with `XcodeOpenWorkspace`. Until then every tool says the agent isn't approved. It returns a workspace identifier to pass to every call. If that one reports no active scheme, use the `windowtab-…` identifier `XcodeListWorkspaces` lists for the same project.
- **The scheme is CueCan and the destination My Mac.** Xcode generates the scheme, so there's no `.xcscheme` file.
- **Build issues:** `BuildProject` is incremental, and `GetBuildLog` shows only the issues from tasks that ran in the last build. For a file's current errors and warnings use `XcodeRefreshCodeIssuesInFile` with its path in the project, such as `CueCan/Recording/RecorderModel.swift`. If it fails with "SourceEditorCallableDiagnosticError error 5" right after a build, call it again. Don't pass `glob` to `GetBuildLog`.
- **Running:** `RunProject` builds and launches, and `StopProject` quits. Quitting that way skips Stop, so stop the recording or close the setup bar first.
- **The console:** `GetConsoleOutput`, with `oslogSeverity: ["error", "fault"]` to filter it.
- **The debugger:** `RunProject` with `attachDebugger: true`, then `InvokeDebuggerCommand`.
- **The package can't be reached this way.** It's the app's local package and has no scheme of its own, so its tests run from the shell.

## What automation can't check

- **Drags.** Screen-control tools have refused to press and drag on CueCan's windows. Dragging the panel, the capture area's corners or anything in the timeline needs a person.
- **Keys in a panel.** They refuse keystrokes while one of CueCan's panels holds the keyboard, which the setup bar does by design. Esc and Return there need a person.
- **Clicks work.** Another app's invisible window can still block a click at one spot.
- **Real devices.** Tracks staying in sync over a long take, a microphone unplugged mid-take, a camera that stops sending pictures.

Say plainly which of these you couldn't check.

---
name: cuecan-ui
description: Build or change anything a person sees in CueCan for Mac: a window, a settings row, a floating panel, a menu, a popover, a notice, a button label or an error. Covers the house rules for wording and layout, the app's own building blocks for panels, menus and inspectors, how an editor gesture becomes a saved edit, and what to check before calling it done. Use for any user-facing change, including "just the text".
---

# What a person sees

## Words

The bar is high and the rule is short: **a title, and one short line at most.**

- **Cut the explanation.** If people already know what a thing is, don't tell them. A confirmation is its question and two buttons.
- **No measurements in a notice.** Say what happened, not by how many pixels.
- **Say what happened, not what can't.** "Was unable to grow", not "can't grow": the app only knows this attempt failed.
- **An error says what went wrong in words a creator understands,** and what to do if there's something to do. No error codes, no type names.
- **Buttons are verbs** that name the result: "Move to Trash", "Start a recording".
- **Name things by what they are.** Shapes are "16:9" and "9:16".
- **A control that's off says why on hover** (`.help`).
- **Nothing a person reads is invented:** no made-up numbers, sizes or times. If the true figure isn't known, leave it out.

## Layout

- **A settings row is a title, one line under it, and one control at the trailing edge,** so the titles, the second lines and the controls each line up down the form. Use a grouped `Form` and let it bring its own margins.
- **Use system materials and semantic colours,** not hard-coded hex. Check light and dark.
- **Panels that float over other apps are dark,** because they sit over anything.
- **A row of the same thing is the same height,** whatever it holds.

## The app's building blocks

Use these before reaching for a plain SwiftUI equivalent.

| For | Use | Why |
| --- | --- | --- |
| A panel over other apps (the setup bar, the Recording Panel, the capture area) | `OverlayPanel`, `HostedPanel` | Borderless, on every Space, never in a recording, and never activates the app |
| A menu with a custom label | `PopUpMenu` | A real `NSMenu`: clicking away or Esc closes it and nothing happens |
| An inspector in the editor | `InspectorPopover` | One at a time; Escape dismisses it before it changes the selection |
| A change to the edit | `EditorModel.change(_:_:)` | Saves with an author and a reason, so undo works and an agent sees it |

The app is a menu bar app. Its windows are Projects, Settings and the first-run setup, and it gets a Dock icon only while Projects is open.

## A gesture is an edit

Every editor gesture is one of the edit's operations in ProjectKit, saved through `EditorModel.change`. Don't change the edit's state in a view. If the operation doesn't exist yet, add it to ProjectKit with tests first (the `cuecan-edit-model` skill).

## Accessibility

- An icon-only button has an `accessibilityLabel`.
- A row that reads as one thing is one element (`accessibilityElement(children: .combine)`), with its actions named.
- Decoration is hidden from assistive technology.

## Before calling it done

1. **See it.** Use a `#Preview` (inside `#if DEBUG`), or run the app (the `cuecan-run-app` skill). The floating panels are left out of screen capture unless a debug setting is on.
2. **Read every word again** and cut what isn't needed.
3. **Check both appearances,** and the narrowest size the window allows.
4. **Say what you saw and what you didn't.** Drags, and keys inside a panel, need a person.

For SwiftUI API choices, the `swiftui-pro` skill reviews the code itself.

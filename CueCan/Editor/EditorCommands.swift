import AppKit
import ProjectKit
import SwiftUI

private struct EditorModelKey: FocusedValueKey {
    typealias Value = EditorModel
}

extension FocusedValues {
    var editorModel: EditorModel? {
        get { self[EditorModelKey.self] }
        set { self[EditorModelKey.self] = newValue }
    }
}

/// The same actions in the menu bar and beside the timeline. Editing remains available without
/// memorizing shortcuts or guessing which lane accepts a right-click.
struct EditorCommands: Commands {
    @FocusedValue(\.editorModel) private var model

    var body: some Commands {
        CommandMenu("Timeline") {
            if let model {
                TimelineActions(model: model)
            } else {
                Button("Open a take to edit") {}.disabled(true)
            }
        }
    }
}

/// Commands for the current editor selection, in the menu bar and beside the timeline.
///
/// Each item shows its key, but `EditorKeys` does the work: its monitor takes the editor's keys before the
/// menu sees them, and leaves them alone while a text field or a sheet has the keyboard. A key that does
/// reach an item was meant for that field, so it goes on to it instead of editing the timeline.
struct TimelineActions: View {
    let model: EditorModel

    var body: some View {
        Group {
            item("Split at playhead", "b", .command) { model.blade(at: model.currentTime) }
            item("Delete selection", .delete, []) { model.deleteSelection() }
                .disabled(model.selection.isEmpty && model.markedRange == nil)
            Menu("Trim to playhead") {
                item("Trim start", "[", .option) { model.trimToPlayhead(.start) }
                item("Trim end", "]", .option) { model.trimToPlayhead(.end) }
            }
            Divider()
            // The broad pass, without an agent: the selected clips, or the whole edit.
            Button(model.passScope == nil ? "Remove silences" : "Remove silences in selection") { model.removeSilences() }
            Divider()
            Button("Add overlay…") {
                model.pause()
                if let url = OverlayFiles.choose() { model.addOverlay(url) }
            }
            item("Hold screen", "h", .shift) { model.freezeSelection() }
                .disabled(model.selectedRange == nil && model.selectedClip == nil)
            Divider()
            item("Mark In", "i", []) { model.mark(in: true) }
            item("Mark Out", "o", []) { model.mark(in: false) }
            item("Clear In and Out", "x", .option) { model.clearMarks() }
                .disabled(model.markIn == nil && model.markOut == nil)
            item("Add marker", "m", []) { model.addMarker() }
            Divider()
            item("Fit timeline", "z", .shift) { model.fitRequest += 1 }
        }
        .disabled(model.timeline == nil)
    }

    private func item(_ title: String, _ key: KeyEquivalent, _ modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        Button(title) {
            if let event = NSApp.currentEvent, event.type == .keyDown,
               event.charactersIgnoringModifiers?.lowercased() == String(key.character) {
                NSApp.keyWindow?.firstResponder?.keyDown(with: event)
            } else {
                action()
            }
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}

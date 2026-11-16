import AppKit
import Carbon.HIToolbox
import SwiftUI

/// New recording…, the one way to start a recording (docs/ui.md, R1; docs/decisions.md, 78), defined once
/// for the global shortcut, the menu bar menu and the File menu, so their title and shortcut can't drift
/// apart. The setup bar opens on the format used last.
///
/// The shortcut uses ⌃⌥⌘, which macOS leaves free, as does ⌃⌥⌘P for the Recording Panel.
struct RecordingCommand {
    let title: String
    let systemImage: String
    /// The key with ``modifiers``, as menus show it.
    let key: KeyEquivalent
    /// The same key for `RegisterEventHotKey`.
    let keyCode: Int

    /// The modifiers every recording shortcut uses.
    static let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]

    static let newRecording = RecordingCommand(title: "New recording…", systemImage: "record.circle", key: .return, keyCode: kVK_Return)

    func perform(in app: AppModel) {
        app.recorder.openSetup()
    }

    /// The key as an `NSMenuItem` key equivalent.
    var menuKeyEquivalent: String {
        key == .return ? "\r" : String(key.character)
    }

    /// The shortcut for SwiftUI's commands.
    var shortcut: KeyboardShortcut {
        KeyboardShortcut(key, modifiers: [.control, .option, .command])
    }
}

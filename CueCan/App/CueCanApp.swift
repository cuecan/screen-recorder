import SwiftUI

/// A menu bar app (`LSUIElement`) that gets a Dock icon only while the projects window is open
/// (docs/decisions.md, 29). The menu bar item is an `NSStatusItem` (``StatusItemController``), so its
/// menu can be built fresh for each click: the recording commands, or the recording's status and controls.
/// The screens are specified in docs/ui.md.
@main
struct CueCanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Projects", id: "projects") {
            ProjectsView()
                .environment(delegate.app)
        }
        .defaultSize(width: 1280, height: 800)
        // A first launch opens the setup window instead; Projects follows when it's closed.
        .defaultLaunchBehavior(AccessSetupModel.isNeeded ? .suppressed : .presented)
        .commands {
            EditorCommands()
            CommandGroup(after: .newItem) {
                let command = RecordingCommand.newRecording
                Button(command.title) { command.perform(in: delegate.app) }
                    .keyboardShortcut(command.shortcut)
                Button("Open last project") { delegate.app.openLastProject() }
                    .keyboardShortcut("z", modifiers: [.option, .command])
                // A copy of the open take with its own edit, over the same recordings (docs/decisions.md, 77).
                Button("Duplicate") { if let url = delegate.app.openProject { delegate.app.duplicate(url) } }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(delegate.app.openProject == nil)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Background Tasks") { delegate.app.showBackgroundTasks() }
                    .keyboardShortcut("9", modifiers: .command)
                // Also ⌃⌥⌘P from any app, and in the menu bar menu while setting up or recording.
                Button("Show or Hide Recording Panel") { delegate.app.recorder.panel.toggleShown() }
                    .keyboardShortcut("p", modifiers: [.control, .option, .command])
            }
        }

        // First run: access, then connecting Claude (docs/ui.md, board 11). Settings opens it again.
        Window("Set Up CueCan", id: "setup") {
            AccessSetupView()
                .environment(delegate.app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(AccessSetupModel.isNeeded ? .presented : .suppressed)

        Settings {
            SettingsView()
                .environment(delegate.app)
        }
    }
}

/// Owns what lives outside SwiftUI's scenes: the menu bar item, the global shortcuts and the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    private var statusItem: StatusItemController?
    private var hotKeys: GlobalHotKeys?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(app: app)
        hotKeys = GlobalHotKeys(app: app)
    }

    /// Clicking the Dock icon with no window open reopens Projects (docs/decisions.md, 29).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { app.showProjects() }
        return true
    }

    /// Closing the last window leaves CueCan running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

import AppKit
import ProjectKit
import RecorderKit
import SwiftUI
import UpdateKit

/// CueCan's menu bar item (docs/ui.md, R1; docs/decisions.md, 29 and 50).
///
/// Its icon is CueCan's logo at all times, never a timer or a record symbol, because a full-screen
/// recording shows the menu bar. It always opens a plain menu: the recording commands
/// while nothing is set up; the status and the controls while setting up or recording, so a hidden
/// Recording Panel's controls are always one click away. An `NSStatusItem` rather than a `MenuBarExtra`,
/// so the menu can be built fresh for each click.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let app: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    /// The menu last opened, kept alive until the next one, so the chosen item's action always arrives.
    private var openMenu: NSMenu?

    init(app: AppModel) {
        self.app = app
        super.init()
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("CueCan")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            // SwiftUI's window actions, from the moment the app launches, so Show projects works even
            // when the projects window wasn't opened at launch.
            let actions = NSHostingView(rootView: SceneActionsReader(app: app))
            actions.frame = .zero
            button.addSubview(actions)
        }
    }

    @objc private func clicked() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        if app.recorder.isActive {
            addRecordingItems(to: menu)
        } else {
            addStartItems(to: menu)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Background tasks…", symbol: "checklist", key: "9", modifiers: .command) { [app] in app.showBackgroundTasks() })
        menu.addItem(menuItem("Settings…", key: ",", modifiers: .command) { [app] in app.showSettings() })
        let update = menuItem("Check for Updates…", key: "", modifiers: []) { [app] in
            // The menu bar app is rarely in front, and Sparkle's window would open behind the others.
            NSApp.activate()
            app.updater.checkForUpdates()
        }
        update.isEnabled = app.updater.canCheckForUpdates
        menu.addItem(update)
        menu.addItem(menuItem("Quit CueCan", key: "q", modifiers: .command) { NSApp.terminate(nil) })
        openMenu = menu
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Taken off again, so the next click comes to `clicked` and builds a fresh menu. Not at once: the
        // chosen item's action is sent after the menu closes, and needs the menu alive.
        DispatchQueue.main.async { [weak self] in self?.item.menu = nil }
    }

    // MARK: - Nothing set up

    private func addStartItems(to menu: NSMenu) {
        let command = RecordingCommand.newRecording
        menu.addItem(menuItem(command.title, symbol: command.systemImage, key: command.menuKeyEquivalent, modifiers: RecordingCommand.modifiers) { [app] in
            command.perform(in: app)
        })
        menu.addItem(.separator())
        menu.addItem(menuItem("Show projects", key: "0", modifiers: .command) { [app] in app.showProjects() })
        menu.addItem(menuItem("Open last project", key: "z", modifiers: [.option, .command]) { [app] in app.openLastProject() })
    }

    // MARK: - Setting up or recording

    /// The status, the controls, and how the Recording Panel shows.
    private func addRecordingItems(to menu: NSMenu) {
        let recorder = app.recorder
        let status = menuItem(Self.status(of: recorder), key: "", modifiers: []) {}
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        switch recorder.phase {
        case .settingUp:
            let start = menuItem("Start recording", symbol: "record.circle", key: "", modifiers: []) { recorder.startRecording() }
            start.isEnabled = recorder.startConditions.canStart
            start.toolTip = recorder.startConditions.blocker
            menu.addItem(start)
            menu.addItem(menuItem("Cancel", key: "", modifiers: []) { recorder.closeSetup() })
        case .recording, .paused:
            let paused = recorder.phase == .paused
            let pause = menuItem(paused ? "Resume" : "Pause", symbol: paused ? "play.fill" : "pause.fill", key: "", modifiers: []) { recorder.togglePause() }
            pause.isEnabled = recorder.canPause
            menu.addItem(pause)
            let stop = menuItem("Stop", symbol: "stop.fill", key: "", modifiers: []) { Task { await recorder.stop() } }
            stop.isEnabled = recorder.canStop
            menu.addItem(stop)
            // Two deliberate choices, as in the panel (docs/decisions.md, 51).
            let discard = NSMenuItem(title: "Discard", action: nil, keyEquivalent: "")
            discard.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            discard.isEnabled = recorder.canDiscard
            let choices = NSMenu()
            choices.autoenablesItems = false
            for action in DiscardAction.allCases {
                let item = menuItem(action.title, symbol: action.systemImage, key: "", modifiers: []) { action.perform(in: recorder) }
                if action.isDestructive {
                    item.attributedTitle = NSAttributedString(string: action.title, attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)])
                }
                choices.addItem(item)
            }
            discard.submenu = choices
            menu.addItem(discard)
        default:
            break
        }

        menu.addItem(.separator())
        let panel = recorder.panel
        let shown = panel.choice != .hidden
        menu.addItem(menuItem(shown ? "Hide Recording Panel" : "Show Recording Panel", key: "p", modifiers: RecordingCommand.modifiers) {
            panel.toggleShown()
        })
        // What the panel shows (docs/decisions.md, 82): the preview of the export, or the camera alone.
        for choice in [FloatingPanelChoice.preview, .camera] {
            let item = menuItem(choice.title, key: "", modifiers: []) { panel.choose(choice) }
            item.state = panel.choice == choice ? .on : .off
            item.indentationLevel = 1
            if choice == .camera, !recorder.isCameraOn {
                item.isEnabled = false
                item.toolTip = "No camera to show"
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Show projects", key: "0", modifiers: .command) { [app] in app.showProjects() })
    }

    /// "Recording · 3:12 · Both · Split", "Ready · Both · camera only", or "Ready · No format chosen".
    private static func status(of recorder: RecorderModel) -> String {
        let format = recorder.formatLabel
        let timer = Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond))
        if recorder.phase == .saving || recorder.phase == .discarding { return recorder.phase.statusTitle }
        let parts = recorder.phase.showsElapsed ? [recorder.phase.statusTitle, timer, format] : [recorder.phase.statusTitle, format]
        return parts.joined(separator: " · ")
    }

    private func menuItem(_ title: String, symbol: String? = nil, key: String, modifiers: NSEvent.ModifierFlags, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let menuItem = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        menuItem.keyEquivalentModifierMask = modifiers
        if let symbol { menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return menuItem
    }
}

/// Reads SwiftUI's window actions into the app model, so AppKit code can open the projects window and Settings.
private struct SceneActionsReader: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                app.openWindow = openWindow
                app.openSettings = openSettings
            }
    }
}

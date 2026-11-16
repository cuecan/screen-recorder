import AppKit
import SwiftUI

/// The Dock icon follows the projects window (docs/decisions.md, 29; docs/ui.md, R7).
///
/// While the projects window is open, CueCan is a regular app: a Dock icon, Cmd-Tab and its own menus.
/// Closing it takes them away again. While recording, the window tucks away and the Dock icon goes with
/// it, so nothing of CueCan's is in Cmd-Tab while the creator flips between apps; both come back on Stop.
/// The setup bar, the area and the Recording Panel are non-activating panels, so they never bring it up.
final class DockIconController {
    /// The projects window, while it's open.
    private(set) weak var projectsWindow: NSWindow?
    /// Tucking away with no window open still suppresses the Dock until recording ends.
    private enum Presentation {
        case available
        case tucked(window: NSWindow?)
    }

    private var presentation = Presentation.available
    private var closeObserver: (any NSObjectProtocol)?
    /// The first-run setup window, while it's open. It needs the Dock icon as much as Projects does: the
    /// creator leaves for System Settings and has to find the way back.
    private weak var setupWindow: NSWindow?
    private var setupCloseObserver: (any NSObjectProtocol)?

    private var isTucked: Bool {
        if case .tucked = presentation { return true }
        return false
    }

    /// The projects window is about to open or come forward.
    func projectsWindowWillOpen() {
        if isTucked { return }
        setPolicy(.regular)
    }

    /// The projects window is on screen.
    func projectsWindowAppeared(_ window: NSWindow) {
        guard projectsWindow !== window else { return }
        projectsWindow = window
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.projectsWindowClosed() }
        }
        // It's about to show.
        if !isTucked { setPolicy(.regular) }
    }

    /// The setup window is on screen.
    func setupWindowAppeared(_ window: NSWindow) {
        guard setupWindow !== window else { return }
        setupWindow = window
        if let setupCloseObserver { NotificationCenter.default.removeObserver(setupCloseObserver) }
        setupCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setupWindow = nil
                self?.update()
            }
        }
        setPolicy(.regular)
    }

    private func projectsWindowClosed() {
        projectsWindow = nil
        if isTucked { presentation = .tucked(window: nil) }
        update()
    }

    /// Recording is starting: the projects window and the Dock icon go.
    func tuckAway() {
        guard !isTucked else { return }
        let window = projectsWindow.flatMap { $0.isVisible ? $0 : nil }
        presentation = .tucked(window: window)
        window?.orderOut(nil)
        update()
    }

    /// Stop, Discard or a cancelled start: both come back if the window was open.
    func bringBack() {
        guard case .tucked(let window) = presentation else { return }
        presentation = .available
        if let window {
            setPolicy(.regular)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        update()
    }

    private func update() {
        let open = projectsWindow?.isVisible ?? false
        setPolicy((open && !isTucked) || setupWindow != nil ? .regular : .accessory)
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}

/// Tells the Dock icon controller which window the projects view is in.
struct ProjectsWindowReporter: NSViewRepresentable {
    let dock: DockIconController

    func makeNSView(context: Context) -> ReportingView {
        ReportingView(dock: dock)
    }

    func updateNSView(_ view: ReportingView, context: Context) {}

    final class ReportingView: NSView {
        private let dock: DockIconController

        init(dock: DockIconController) {
            self.dock = dock
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { dock.projectsWindowAppeared(window) }
        }
    }
}

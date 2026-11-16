import AppKit
import Observation
import RecorderKit

/// The first-run setup window's state (docs/ui.md, board 11): the access list, kept in step with what macOS
/// reports while the window is open, and the Connect Claude step after it.
///
/// The rows' behaviour is ``AccessChecklist``'s, in the package. This asks macOS, opens System Settings and
/// remembers what was asked, so the window comes back where it was if macOS reopens CueCan.
@Observable
final class AccessSetupModel {
    /// Set once the window has been closed or finished, so it isn't shown at the next launch.
    static let doneKey = "accessSetupDone"
    static let askedKey = "accessSetupAsked"

    /// Whether the setup window opens at launch, in place of Projects.
    static var isNeeded: Bool { !UserDefaults.standard.bool(forKey: doneKey) }

    enum Step { case access, connect }

    private(set) var list: AccessChecklist
    var step = Step.access
    /// The kinds whose macOS prompt is up, so their button can't be pressed twice.
    private(set) var asking: Set<AccessKind> = []

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let read: (AccessKind) -> AccessStatus
    @ObservationIgnored private let ask: (AccessKind) async -> Void
    @ObservationIgnored private let openSettings: (AccessKind) -> Void

    init(defaults: UserDefaults = .standard,
         read: @escaping (AccessKind) -> AccessStatus = SystemAccess.status(of:),
         ask: @escaping (AccessKind) async -> Void = { await SystemAccess.prompt(for: $0) },
         openSettings: @escaping (AccessKind) -> Void = { PrivacyPane($0).open() }) {
        self.defaults = defaults
        self.read = read
        self.ask = ask
        self.openSettings = openSettings
        let asked = (defaults.stringArray(forKey: Self.askedKey) ?? []).compactMap(AccessKind.init(rawValue:))
        list = AccessChecklist(asked: Set(asked))
        refresh()
    }

    /// A row's button.
    func press(_ kind: AccessKind) {
        guard !asking.contains(kind), let action = list.press(kind) else { return }
        defaults.set(list.asked.map(\.rawValue).sorted(), forKey: Self.askedKey)
        switch action {
        case .openSettings(let kind):
            openSettings(kind)
        case .prompt(let kind):
            asking.insert(kind)
            Task {
                await ask(kind)
                asking.remove(kind)
                refresh()
            }
        }
    }

    /// Puts the window in front of every app's windows. CueCan starts as a menu bar app, which macOS doesn't
    /// make active at launch, so a window that is only shown opens behind whatever was in front.
    func bringForward() {
        window?.orderFrontRegardless()
        NSApp.activate()
        window?.makeKey()
    }

    /// Reads what macOS reports now.
    func refresh() {
        for kind in AccessKind.allCases {
            let becameAllowed = list.update(kind, to: read(kind))
            // The switch was turned on in System Settings: the window shows itself over it, without taking
            // the keyboard. Not for Screen Recording, where macOS may be asking to quit and reopen CueCan.
            if becameAllowed, kind != .screenRecording, !NSApp.isActive { window?.orderFrontRegardless() }
        }
    }

    /// Follows macOS while the window is open: a switch in System Settings has no notification to wait for.
    func startFollowing() {
        guard polling == nil else { return }
        refresh()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.refresh()
            }
        }
    }

    func stopFollowing() {
        polling?.cancel()
        polling = nil
    }

    /// The window was closed or finished by the creator. A quit, or macOS reopening CueCan, isn't this.
    func finish() {
        defaults.set(true, forKey: Self.doneKey)
        stopFollowing()
    }
}

extension PrivacyPane {
    init(_ kind: AccessKind) {
        switch kind {
        case .camera: self = .camera
        case .microphone: self = .microphone
        case .screenRecording: self = .screenRecording
        case .accessibility: self = .accessibility
        }
    }
}

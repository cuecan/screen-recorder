import Foundation

/// One of the kinds of access macOS asks about before CueCan can record (docs/ui.md, board 11).
public enum AccessKind: String, CaseIterable, Sendable, Codable {
    case camera, microphone, screenRecording, accessibility

    /// Recording works without it: Accessibility only snaps windows into the area.
    public var isOptional: Bool { self == .accessibility }

    /// Its name as System Settings lists it under Privacy & Security.
    public var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .screenRecording: "Screen & System Audio Recording"
        case .accessibility: "Accessibility"
        }
    }

    /// What CueCan does with it.
    public var reason: String {
        switch self {
        case .camera: "Records your camera."
        case .microphone: "Records your voice."
        case .screenRecording: "Records your screen and your Mac’s sound."
        case .accessibility: "Snaps windows into the recording area."
        }
    }

    /// What to do in System Settings, shown while the row waits for the switch.
    public var settingsInstruction: String {
        switch self {
        case .camera, .microphone, .accessibility:
            "Turn on CueCan in System Settings."
        case .screenRecording:
            "Turn on CueCan in System Settings, then choose Quit & Reopen."
        }
    }

    /// Whether macOS answers in its own prompt, with nothing to do in System Settings. Camera and microphone
    /// do, the first time they're asked for; the others are switches in System Settings.
    public var isAnsweredInThePrompt: Bool { self == .camera || self == .microphone }
}

/// What macOS says about one kind of access.
public enum AccessStatus: Sendable, Equatable {
    /// Not allowed, and macOS hasn't said it was refused: it may never have been asked for.
    case undecided
    /// Refused, or switched off. Only System Settings can change it.
    case denied
    case allowed
}

/// The first-run list of access: what each row shows and what its button does.
///
/// It holds no system calls, so the whole interaction is tested without a Mac's privacy database. The app
/// feeds it what macOS reports (``update(_:to:)``) and does what ``press(_:)`` returns.
public struct AccessChecklist: Sendable, Equatable {
    /// What a row shows.
    public enum RowState: Sendable, Equatable {
        /// An Allow button, which asks macOS.
        case ask
        /// What to do in System Settings, and a button that opens it.
        case waiting
        case allowed
    }

    /// What pressing a row's button does.
    public enum Action: Sendable, Equatable {
        /// Ask macOS, which shows its own prompt and adds CueCan to the list in System Settings.
        case prompt(AccessKind)
        case openSettings(AccessKind)
    }

    public private(set) var statuses: [AccessKind: AccessStatus]
    /// The kinds already asked for whose answer is a switch in System Settings. Kept between launches, since
    /// macOS shows its prompt for them once, and may quit CueCan when the switch is turned on.
    public private(set) var asked: Set<AccessKind>

    public init(statuses: [AccessKind: AccessStatus] = [:], asked: Set<AccessKind> = []) {
        self.statuses = statuses
        self.asked = asked
    }

    public func status(of kind: AccessKind) -> AccessStatus { statuses[kind] ?? .undecided }

    public func state(of kind: AccessKind) -> RowState {
        switch status(of: kind) {
        case .allowed: .allowed
        case .denied: .waiting
        case .undecided: asked.contains(kind) ? .waiting : .ask
        }
    }

    /// The row's button was pressed. Nil when there's nothing to do.
    public mutating func press(_ kind: AccessKind) -> Action? {
        switch state(of: kind) {
        case .allowed:
            return nil
        case .waiting:
            return .openSettings(kind)
        case .ask:
            // Camera and microphone stay as they are until macOS's prompt is answered, so the row never says
            // to go to System Settings while that prompt is up.
            if !kind.isAnsweredInThePrompt { asked.insert(kind) }
            return .prompt(kind)
        }
    }

    /// Takes what macOS reports now. True when this kind has just become allowed.
    @discardableResult
    public mutating func update(_ kind: AccessKind, to status: AccessStatus) -> Bool {
        let wasAllowed = self.status(of: kind) == .allowed
        statuses[kind] = status
        return status == .allowed && !wasAllowed
    }

    /// Whether CueCan can record a screen, a camera and a voice: everything but the optional kinds.
    public var canRecord: Bool { AccessKind.allCases.filter { !$0.isOptional }.allSatisfy { status(of: $0) == .allowed } }

    public var isComplete: Bool { missing.isEmpty }

    /// The kinds not allowed yet, in the order they're listed.
    public var missing: [AccessKind] { AccessKind.allCases.filter { status(of: $0) != .allowed } }
}

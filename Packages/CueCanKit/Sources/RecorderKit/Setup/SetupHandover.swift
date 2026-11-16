import Foundation

/// The setup window may finish its animation before or after capture begins. It stays available for a
/// startup failure, then retires once both the animation and recording have started.
public struct SetupHandover: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case animating(UUID)
        case waitingForRecording(UUID)
    }
    public private(set) var state: State = .idle
    public init() {}
    public var isLeaving: Bool { state != .idle }

    public mutating func begin() -> UUID {
        let id = UUID()
        state = .animating(id)
        return id
    }

    public func accepts(_ id: UUID, phase: RecordingPhase) -> Bool {
        guard phase.allowsPanelHandOver else { return false }
        switch state {
        case .animating(let current), .waitingForRecording(let current): return current == id
        case .idle: return false
        }
    }

    /// True when the hidden setup window can release its native views immediately.
    public mutating func animationFinished(_ id: UUID, phase: RecordingPhase) -> Bool {
        guard accepts(id, phase: phase) else { return false }
        state = .waitingForRecording(id)
        return phase.isRecording
    }

    /// Called when capture begins; an unfinished animation still owns the window until it completes.
    public var canRetireAfterRecordingStarted: Bool {
        if case .waitingForRecording = state { true } else { false }
    }

    public mutating func cancel() { state = .idle }
}

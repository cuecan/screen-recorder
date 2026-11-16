import Foundation

/// Serial processing with one coalesced follow-up pass when settings change during work.
public struct ProcessingQueue: Sendable {
    public struct Attempt: Equatable, Sendable {
        public let project: URL
        public let id: UUID
    }
    public enum State: Equatable, Sendable {
        case queued
        case running(Attempt, message: String)
        case runningWithPendingChanges(Attempt, message: String)
        case failed(String)

        public var activity: String? {
            switch self {
            case .queued: "Waiting"
            case .running(_, let message), .runningWithPendingChanges(_, let message): message
            case .failed: nil
            }
        }
        fileprivate var attempt: Attempt? {
            switch self {
            case .running(let attempt, _), .runningWithPendingChanges(let attempt, _): attempt
            default: nil
            }
        }
    }
    public private(set) var states: [URL: State] = [:]
    private var waiting: [URL] = []

    public init() {}

    public mutating func request(_ project: URL) {
        switch states[project] {
        case .queued, .runningWithPendingChanges: break
        case .running(let attempt, let message):
            states[project] = .runningWithPendingChanges(attempt, message: message)
        case .failed, nil:
            states[project] = .queued
            waiting.append(project)
        }
    }

    /// Reserves the worker synchronously, before the caller launches asynchronous work.
    public mutating func startNext() -> Attempt? {
        guard !states.values.contains(where: { $0.attempt != nil }), !waiting.isEmpty else { return nil }
        let project = waiting.removeFirst()
        let attempt = Attempt(project: project, id: UUID())
        states[project] = .running(attempt, message: "Starting")
        return attempt
    }

    public mutating func progress(_ message: String, for attempt: Attempt) {
        guard states[attempt.project]?.attempt == attempt else { return }
        if case .runningWithPendingChanges = states[attempt.project] {
            states[attempt.project] = .runningWithPendingChanges(attempt, message: message)
        } else {
            states[attempt.project] = .running(attempt, message: message)
        }
    }

    public mutating func finish(_ attempt: Attempt, problem: String?) {
        guard states[attempt.project]?.attempt == attempt else { return }
        if case .runningWithPendingChanges = states[attempt.project] {
            states[attempt.project] = .queued
            waiting.append(attempt.project)
        } else {
            states[attempt.project] = problem.map(State.failed)
        }
    }
}

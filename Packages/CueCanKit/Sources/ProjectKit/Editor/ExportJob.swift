import Foundation

/// The lifecycle of one export attempt. Progress belongs to an attempt and cannot overwrite its result.
public struct ExportJob: Equatable, Sendable {
    public enum Item: Hashable, Sendable {
        case video(OutputShape), transcript, handoff

        public var label: String {
            switch self {
            case .video(let shape): shape.description
            case .transcript: "Transcript, SRT and text"
            case .handoff: "Timeline, FCPXML, with the transcript"
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case success, cancelled, failed(String)
    }

    public enum Phase: Equatable, Sendable {
        case setup, running, stopping, finished(Outcome)

        public var title: String {
            switch self {
            case .setup: "Export"
            case .running: "Exporting…"
            case .stopping: "Stopping export…"
            case .finished(.success): "Exported"
            case .finished(.cancelled): "Export stopped"
            case .finished(.failed): "Export failed"
            }
        }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case waiting, preparing, running(Double), complete([URL])
        }
        public let id: Item
        public fileprivate(set) var state: State = .waiting
        public var label: String { id.label }
        public var files: [URL] { if case .complete(let files) = state { files } else { [] } }
        public var progress: Double {
            switch state { case .waiting, .preparing: 0; case .running(let value): value; case .complete: 1 }
        }
        public var status: String {
            switch state {
            case .waiting: "Waiting"
            case .preparing: "Preparing…"
            case .running(let value): "\(Int(value * 100))%"
            case .complete: "Done"
            }
        }
    }

    public private(set) var phase: Phase = .setup
    public private(set) var rows: [Row] = []
    public private(set) var warnings: [String] = []
    private var attempt: UUID?

    public init() {}

    /// Starts only from setup; a retry first calls `reset()` after the previous attempt finishes.
    public mutating func start(_ items: [Item]) -> UUID? {
        guard phase == .setup else { return nil }
        let id = UUID()
        attempt = id
        rows = items.map { Row(id: $0) }
        phase = .running
        return id
    }

    public mutating func stop() {
        if phase == .running { phase = .stopping }
    }

    /// Composition and audio preparation have no measured fraction. Keep them distinct from work that
    /// has not started, and never let a late preparation callback reset an encoder's progress.
    public mutating func prepare(_ item: Item, attempt: UUID) {
        guard self.attempt == attempt, phase == .running,
              let index = rows.firstIndex(where: { $0.id == item }), rows[index].state == .waiting else { return }
        rows[index].state = .preparing
    }

    public mutating func update(_ item: Item, progress: Double, attempt: UUID) {
        guard self.attempt == attempt, phase == .running, progress.isFinite,
              let index = rows.firstIndex(where: { $0.id == item }) else { return }
        if case .complete = rows[index].state { return }
        rows[index].state = .running(max(rows[index].progress, min(1, max(0, progress))))
    }

    public mutating func complete(_ item: Item, files: [URL], attempt: UUID) {
        guard self.attempt == attempt, phase == .running || phase == .stopping,
              let index = rows.firstIndex(where: { $0.id == item }) else { return }
        rows[index].state = .complete(files)
    }

    public mutating func finish(_ outcome: Outcome, attempt: UUID, warnings: [String] = []) {
        guard self.attempt == attempt, phase == .running || phase == .stopping else { return }
        self.warnings = warnings
        phase = .finished(outcome)
    }

    public mutating func reset() {
        guard case .finished = phase else { return }
        self = ExportJob()
    }
}

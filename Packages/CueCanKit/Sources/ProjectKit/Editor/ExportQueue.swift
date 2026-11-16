import Foundation

/// A serial queue whose exports outlive the sheet or editor that requested them. Work is reserved
/// synchronously before the front end starts a task; late callbacks cannot release another export.
public struct ExportQueue: Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public fileprivate(set) var job = ExportJob()
        fileprivate let items: [ExportJob.Item]
        public var isActive: Bool {
            switch job.phase { case .setup, .running, .stopping: true; case .finished: false }
        }
        public var status: String { job.phase == .setup ? "Queued" : job.phase.title }
    }

    public struct Attempt: Equatable, Sendable {
        public let entry: UUID
        public let token: UUID
    }

    public private(set) var entries: [Entry] = []
    public private(set) var active: Attempt?
    public init() {}

    @discardableResult
    public mutating func enqueue(title: String, items: [ExportJob.Item]) -> UUID? {
        guard !items.isEmpty else { return nil }
        let entry = Entry(id: UUID(), title: title, items: items)
        entries.append(entry)
        return entry.id
    }

    public mutating func startNext() -> Attempt? {
        guard active == nil, let index = entries.firstIndex(where: { $0.job.phase == .setup }),
              let token = entries[index].job.start(entries[index].items) else { return nil }
        let attempt = Attempt(entry: entries[index].id, token: token)
        active = attempt
        return attempt
    }

    public mutating func update(_ item: ExportJob.Item, progress: Double, for attempt: Attempt) {
        guard active == attempt, let index = index(attempt.entry) else { return }
        entries[index].job.update(item, progress: progress, attempt: attempt.token)
    }

    public mutating func prepare(_ item: ExportJob.Item, for attempt: Attempt) {
        guard active == attempt, let index = index(attempt.entry) else { return }
        entries[index].job.prepare(item, attempt: attempt.token)
    }

    public mutating func complete(_ item: ExportJob.Item, files: [URL], for attempt: Attempt) {
        guard active == attempt, let index = index(attempt.entry) else { return }
        entries[index].job.complete(item, files: files, attempt: attempt.token)
    }

    /// Only a running attempt may publish new outputs. Stopping and duplicate completion callbacks
    /// must not move files after cancellation or publish the same output twice.
    public func accepts(_ item: ExportJob.Item, for attempt: Attempt) -> Bool {
        guard active == attempt, let index = index(attempt.entry), entries[index].job.phase == .running,
              let row = entries[index].job.rows.first(where: { $0.id == item }) else { return false }
        if case .complete = row.state { return false }
        return true
    }

    /// Returns true only when an in-flight task must be cancelled. A queued export stops immediately.
    @discardableResult
    public mutating func stop(_ id: UUID, warnings: [String] = []) -> Bool {
        guard let index = index(id) else { return false }
        switch entries[index].job.phase {
        case .setup:
            if let token = entries[index].job.start(entries[index].items) {
                entries[index].job.finish(.cancelled, attempt: token, warnings: warnings)
            }
            return false
        case .running:
            entries[index].job.stop()
            return true
        case .stopping, .finished:
            return false
        }
    }

    public mutating func finish(_ outcome: ExportJob.Outcome, for attempt: Attempt, warnings: [String] = []) {
        guard active == attempt, let index = index(attempt.entry) else { return }
        entries[index].job.finish(outcome, attempt: attempt.token, warnings: warnings)
        active = nil
    }

    /// Completed files remain discoverable until the creator dismisses them, without clearing work.
    public mutating func clearFinished() { entries.removeAll { !$0.isActive } }

    private func index(_ id: UUID) -> Int? { entries.firstIndex { $0.id == id } }
}

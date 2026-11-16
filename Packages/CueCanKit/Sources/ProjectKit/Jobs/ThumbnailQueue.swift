import Foundation

/// A serial thumbnail queue whose completions must still match the requested project revision.
public struct ThumbnailQueue: Sendable {
    public struct Request: Equatable, Sendable {
        public let id: UUID
        public let project: URL
        public let revision: Int
    }
    public enum Worker: Equatable, Sendable { case idle, running(Request) }
    public private(set) var worker = Worker.idle
    private var wanted: [URL: Request] = [:]
    private var completed: [URL: Int] = [:]
    private var waiting: [Request] = []

    public init() {}

    public func hasCompleted(_ project: URL, revision: Int) -> Bool { completed[project] == revision }

    public mutating func request(_ project: URL, revision: Int) {
        guard completed[project] != revision, wanted[project]?.revision != revision else { return }
        let request = Request(id: UUID(), project: project, revision: revision)
        wanted[project] = request
        waiting.removeAll { $0.project == project }
        waiting.append(request)
    }

    public mutating func startNext() -> Request? {
        guard worker == .idle, !waiting.isEmpty else { return nil }
        let request = waiting.removeFirst()
        worker = .running(request)
        return request
    }

    /// Releases the worker and returns whether this result may be published.
    public mutating func finish(_ request: Request) -> Bool {
        guard worker == .running(request) else { return false }
        worker = .idle
        guard wanted[request.project] == request else { return false }
        completed[request.project] = request.revision
        wanted[request.project] = nil
        return true
    }

    public mutating func forget(_ project: URL) {
        wanted[project] = nil
        completed[project] = nil
        waiting.removeAll { $0.project == project }
    }
}

import Foundation

/// One preview update in flight and only the latest waiting demand. Transient view removal during a
/// layout change cannot queue a needless stop followed by a restart.
public struct PreviewDemandQueue: Sendable {
    public struct Request: Sendable, Equatable {
        public let id: UUID
        public let target: PreviewTarget?
    }
    private enum State: Sendable { case idle, applying(Request) }
    private var state = State.idle
    private var pending: Request?
    public init() {}

    /// Returns an operation only when a worker needs to start. Otherwise replaces the waiting demand.
    public mutating func request(_ target: PreviewTarget?) -> Request? {
        let request = Request(id: UUID(), target: target)
        if case .idle = state { state = .applying(request); return request }
        pending = request
        return nil
    }

    /// Only the active operation can advance the queue. Nil means the worker is finished.
    public mutating func completed(_ request: Request) -> Request? {
        guard case .applying(let active) = state, active.id == request.id else { return nil }
        if let next = pending {
            pending = nil
            state = .applying(next)
            return next
        }
        state = .idle
        return nil
    }
}

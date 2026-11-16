import Foundation

/// Coalesces rapid scrubs into one seek in flight and the newest waiting target. Letting a seek finish
/// gives AVPlayer a chance to display a frame; starting each pointer update immediately cancels it.
public struct PreviewSeeking: Equatable, Sendable {
    public struct Request: Equatable, Sendable {
        public let id: UUID
        public let time: TimeInterval
    }
    public enum Completion: Equatable, Sendable {
        case stale
        case settled
        case next(Request)
    }

    /// A waiting target can exist only while a seek is in flight.
    public enum State: Equatable, Sendable {
        case idle
        case seeking(Request, waiting: TimeInterval?)
    }
    public private(set) var state: State = .idle
    public var active: Request? { if case .seeking(let request, _) = state { request } else { nil } }

    /// The playhead the creator has requested while decoding catches up.
    public var target: TimeInterval? {
        if case .seeking(let request, let waiting) = state { waiting ?? request.time } else { nil }
    }

    public init() {}

    /// Returns work only when no seek is running. A burst replaces its waiting target rather than
    /// accumulating a queue the preview would need to catch up with after the pointer stops.
    public mutating func request(_ time: TimeInterval) -> Request? {
        guard time.isFinite, time >= 0 else { return nil }
        if case .seeking(let active, _) = state {
            state = .seeking(active, waiting: time)
            return nil
        }
        let request = Request(id: UUID(), time: time)
        state = .seeking(request, waiting: nil)
        return request
    }

    /// A cancelled/replaced item's late completion cannot consume the current item's target.
    public mutating func completed(_ request: Request) -> Completion {
        guard case .seeking(let active, let target) = state, active.id == request.id else { return .stale }
        state = .idle
        if let target, target != request.time, let next = self.request(target) { return .next(next) }
        return .settled
    }

    /// Call before replacing the player item or closing the editor.
    public mutating func cancel() {
        state = .idle
    }
}

import Foundation

/// Latest-request-wins loading. A superseded read, composition or seek cannot finish a newer load.
public struct PreviewLoad: Equatable, Sendable {
    /// A completed preview keeps its request identity so a late poster cannot replace a newer one.
    public enum State: Equatable, Sendable {
        case idle
        case loading(UUID)
        /// The new player item is installed, but its initial seek hasn't completed yet.
        case seeking(UUID)
        case ready(UUID)
        case empty
        case failed(String)
    }
    public enum Outcome: Equatable, Sendable { case ready, empty, failed(String) }
    public private(set) var state: State = .idle
    public init() {}
    public var isLoading: Bool {
        switch state {
        case .loading, .seeking: true
        default: false
        }
    }
    public var problem: String? { if case .failed(let message) = state { message } else { nil } }

    public mutating func begin() -> UUID {
        let request = UUID()
        state = .loading(request)
        return request
    }

    public func contains(_ request: UUID) -> Bool { state == .loading(request) || state == .seeking(request) }

    /// Keeps playback's end detection suspended while an item's initial seek is pending. Reinstalling
    /// sound under the same picture preserves the request, so an opening poster can still arrive.
    public mutating func installed(_ request: UUID) {
        guard state == .loading(request) || state == .ready(request) || state == .seeking(request) else { return }
        state = .seeking(request)
    }

    public mutating func finish(_ request: UUID, outcome: Outcome) {
        guard contains(request) else { return }
        state = switch outcome {
        case .ready: .ready(request)
        case .empty: .empty
        case .failed(let message): .failed(message)
        }
    }

    /// Posters belong only to the successfully installed preview, never a cancelled or failed load.
    public func acceptsPoster(for request: UUID) -> Bool { state == .seeking(request) || state == .ready(request) }

    /// Invalidates outstanding work when the editor closes.
    public mutating func cancel() { state = .idle }
}

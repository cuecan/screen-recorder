import Foundation

/// An optional audition of export mastering. Request identities keep old edits and cancellation from
/// publishing readiness for a different mix.
public struct PreviewLoudness: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case off
        case preparing(UUID)
        case ready(UUID, hasAudio: Bool)
        case failed(UUID, String)
    }
    public private(set) var state: State = .off
    public init() {}
    public var isEnabled: Bool { state != .off }
    public var isPreparing: Bool { if case .preparing = state { true } else { false } }
    public mutating func begin() -> UUID {
        let id = UUID()
        state = .preparing(id)
        return id
    }
    public func contains(_ id: UUID) -> Bool {
        if case .preparing(let active) = state { return active == id }
        return false
    }
    public mutating func finish(_ id: UUID, hasAudio: Bool) {
        if contains(id) { state = .ready(id, hasAudio: hasAudio) }
    }
    public mutating func fail(_ id: UUID, message: String) {
        if contains(id) { state = .failed(id, message) }
    }
    public mutating func disable() { state = .off }
}

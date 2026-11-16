import Foundation

/// A calibration's visible state and the identity allowed to update it. Cancelling or retrying invalidates
/// every result from the previous run, including a permission reply that arrives after Cancel.
public struct SyncCalibrationProgress: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case ready
        case starting(UUID)
        case listening(UUID, SyncMeasurement)
        case measured(SyncMeasurement)
        case failed(String)
    }

    public private(set) var state = State.ready
    public init() {}

    public var isRunning: Bool {
        switch state {
        case .starting, .listening: true
        default: false
        }
    }

    public mutating func begin() -> UUID {
        let id = UUID()
        state = .starting(id)
        return id
    }

    public func contains(_ id: UUID) -> Bool {
        switch state {
        case .starting(let request), .listening(let request, _): request == id
        default: false
        }
    }

    public mutating func listening(_ measurement: SyncMeasurement, for id: UUID) {
        if contains(id) { state = .listening(id, measurement) }
    }

    public mutating func complete(_ measurement: SyncMeasurement, for id: UUID) {
        guard contains(id) else { return }
        state = .measured(measurement)
    }

    public mutating func fail(_ message: String, for id: UUID) {
        guard contains(id) else { return }
        state = .failed(message)
    }

    public mutating func reset() {
        state = .ready
    }
}

import Foundation

/// Actual capture readiness, independent of the creator's saved device preference.
/// Startup completions belong to one selection and cannot revive a stopped or replaced device.
public struct DeviceReadiness: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case off
        case requestingPermission
        case starting(CaptureDevice, UUID)
        case ready(CaptureDevice)
        case unavailable(CaptureDevice, reason: String)
    }
    public private(set) var state: State = .off
    public init() {}
    public var isReady: Bool { if case .ready = state { true } else { false } }
    public var isPreparing: Bool {
        switch state { case .requestingPermission, .starting: true; default: false }
    }
    public mutating func requestPermission() { state = .requestingPermission }
    public mutating func stop() { state = .off }
    public mutating func start(_ device: CaptureDevice) -> UUID {
        let attempt = UUID()
        state = .starting(device, attempt)
        return attempt
    }
    public func contains(_ attempt: UUID) -> Bool {
        if case .starting(_, let current) = state { current == attempt } else { false }
    }
    /// Returns false for a completion from a superseded startup.
    @discardableResult
    public mutating func finish(_ attempt: UUID, problem: String?) -> Bool {
        guard case .starting(let device, let current) = state, current == attempt else { return false }
        state = problem.map { .unavailable(device, reason: $0) } ?? .ready(device)
        return true
    }
    public mutating func disconnected(_ device: CaptureDevice) {
        switch state {
        case .ready(let current) where current.id == device.id,
             .starting(let current, _) where current.id == device.id:
            state = .unavailable(device, reason: "The device disconnected.")
        default: break
        }
    }
}

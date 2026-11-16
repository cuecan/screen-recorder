import Foundation

/// One transcript correction being aligned. Superseded and cancelled requests cannot save a result,
/// even when the replacement has exactly the same range and text.
public struct TranscriptFixing: Equatable, Sendable {
    public struct Request: Equatable, Sendable {
        public let id: UUID
        public let range: ItemRange
        public let text: String
    }
    public enum State: Equatable, Sendable { case idle, aligning(Request) }
    public private(set) var state: State = .idle
    public var pending: Request? { if case .aligning(let request) = state { request } else { nil } }
    public init() {}

    public mutating func begin(_ range: ItemRange, text: String) -> Request {
        let request = Request(id: UUID(), range: range, text: text)
        state = .aligning(request)
        return request
    }
    public func contains(_ request: Request) -> Bool { state == .aligning(request) }
    public mutating func finish(_ request: Request) {
        if contains(request) { state = .idle }
    }
    public mutating func cancel() { state = .idle }
}

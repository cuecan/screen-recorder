import Foundation

/// The terminal result of a processing pass, including every source that failed.
public struct ProcessingReport: Codable, Sendable, Equatable {
    public var transcribed: [SourceID] = []
    public var spelled: [SourceID] = []
    public var cleaned: [SourceID] = []
    public var screensRead: [SourceID] = []
    public var failures: [SourceID: String] = [:]
    public init() {}
    public var problem: String? {
        failures.isEmpty ? nil : failures.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
}

import Foundation

/// A run of words that looks like an earlier attempt at the words after it, such as a false start.
/// Marked for Claude to decide on, never cut automatically.
public struct Retake: Codable, Equatable, Sendable {
    /// The earlier attempt.
    public var attempt: ItemRange
    /// The take it was redone as.
    public var redoneAs: ItemRange

    public init(attempt: ItemRange, redoneAs: ItemRange) {
        self.attempt = attempt
        self.redoneAs = redoneAs
    }
}

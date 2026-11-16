import Foundation

/// A stretch of time in seconds, from `start` up to `end`.
public struct TimeRange: Codable, Hashable, Sendable, CustomStringConvertible {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
    public var isEmpty: Bool { end <= start }

    /// Whether the two ranges share any time. Ranges that only touch don't overlap.
    public func overlaps(_ other: TimeRange) -> Bool {
        !isEmpty && !other.isEmpty && start < other.end && other.start < end
    }

    /// This range with another taken out: nothing, one piece or two.
    public func subtracting(_ other: TimeRange) -> [TimeRange] {
        guard overlaps(other), !other.isEmpty else { return isEmpty ? [] : [self] }
        var pieces: [TimeRange] = []
        if other.start > start { pieces.append(TimeRange(start: start, end: other.start)) }
        if other.end < end { pieces.append(TimeRange(start: other.end, end: end)) }
        return pieces
    }

    public var description: String { "\(start)–\(end)" }
}

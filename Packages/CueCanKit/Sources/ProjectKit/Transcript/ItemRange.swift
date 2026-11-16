import Foundation

/// A run of transcript items from one id through another, both included, such as `w_10` through `s_4`.
/// This is how Claude names what to cut, keep or put on the timeline.
public struct ItemRange: Codable, Hashable, Sendable, CustomStringConvertible {
    public var first: TranscriptItemID
    public var last: TranscriptItemID

    public init(first: TranscriptItemID, last: TranscriptItemID) {
        self.first = first
        self.last = last
    }

    /// A range of one item.
    public init(_ item: TranscriptItemID) {
        self.init(first: item, last: item)
    }

    public var description: String {
        first == last ? first.description : "\(first)…\(last)"
    }
}

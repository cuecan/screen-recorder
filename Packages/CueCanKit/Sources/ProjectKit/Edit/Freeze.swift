import Foundation

/// A freeze, such as `f_2`.
public struct FreezeID: PrefixedID {
    public static let prefix = "f"
    public let number: Int
    public init(number: Int) { self.number = number }
}

/// The screen holding on one frame while the camera and the voice play on, for when the creator clicked away
/// too soon (docs/decisions.md, 59). With no screen, the camera is the picture, so the camera holds.
///
/// It's kept in source time, like the transcripts, so it follows every cut: wherever the main track plays
/// ``range`` of ``source``, the picture shows the frame at ``frame`` instead.
public struct Freeze: Codable, Equatable, Sendable, Identifiable {
    public let id: FreezeID
    public var source: SourceID
    /// The stretch of source time that holds.
    public var range: TimeRange
    /// The source time of the frame held. By default the range's start.
    public var frame: TimeInterval

    public init(id: FreezeID, source: SourceID, range: TimeRange, frame: TimeInterval? = nil) {
        self.id = id
        self.source = source
        self.range = range
        self.frame = frame ?? range.start
    }
}

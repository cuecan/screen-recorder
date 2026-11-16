import Foundation

/// What a nudge did: the clip as it now is, and any words the nudged edge now falls inside.
public struct NudgeResult: Equatable, Sendable {
    public var clip: Clip
    /// Where the nudged edge is now, in seconds of source time.
    public var edgeTime: TimeInterval
    /// Words whose aligned times the edge now falls inside: the cut goes through speech rather than silence.
    /// Aligned times can be off, so this is a warning to listen, not proof of a clipped word.
    public var wordsAtEdge: [WordID]
}

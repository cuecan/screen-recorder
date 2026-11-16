/// Small composited pictures for an edge loupe. Nil means that side has no output frame to show.
public struct TrimPreviewFrames: Sendable {
    public let outgoing: Still?
    public let incoming: Still?

    public init(outgoing: Still?, incoming: Still?) {
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

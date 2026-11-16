import Foundation

/// How one source lines up with another: a separate mic or a second angle with the main footage.
///
/// A moment at time `t` in this source happens at `t + offset` in the reference source. The offset is
/// saved, so it can be checked and nudged rather than recomputed.
public struct SourceSync: Codable, Equatable, Sendable {
    /// How the offset was found.
    public enum Method: String, Codable, Sendable {
        /// Recorded by the app on the host clock: exact by construction.
        case hostClock
        /// Found by matching audio waveforms.
        case waveform
        /// Found from both files' timecode.
        case timecode
        /// Set or nudged by hand.
        case manual
    }

    public var reference: SourceID
    public var offset: TimeInterval
    public var method: Method

    public init(reference: SourceID, offset: TimeInterval, method: Method) {
        self.reference = reference
        self.offset = offset
        self.method = method
    }
}

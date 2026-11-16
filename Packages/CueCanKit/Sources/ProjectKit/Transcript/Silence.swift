import Foundation

/// A real silence: a stretch the audio itself shows to be quiet, found by an energy or voice-activity
/// detector. Cut points snap into silences, so the first sound of a word is never clipped.
public struct Silence: Codable, Equatable, Sendable, Identifiable {
    public let id: SilenceID
    public var start: TimeInterval
    public var end: TimeInterval

    public init(id: SilenceID, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

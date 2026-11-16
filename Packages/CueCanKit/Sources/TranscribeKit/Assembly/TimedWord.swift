import Foundation

/// A word as a transcription engine gives it: text and times in seconds, before it has an id.
public struct TimedWord: Sendable, Equatable, Codable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    /// From 0 to 1, when the engine gives one.
    public var confidence: Double?

    public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }

    /// The same word shifted later by `offset` seconds.
    public func offset(by offset: TimeInterval) -> TimedWord {
        TimedWord(text: text, start: start + offset, end: end + offset, confidence: confidence)
    }
}

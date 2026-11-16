import Foundation
import ProjectKit

/// One caption on the edited timeline, with its words' own times so a style can highlight the one being said.
public struct CaptionCue: Equatable, Sendable {
    public struct Word: Equatable, Sendable {
        public var text: String
        public var timeline: TimeRange

        public init(text: String, timeline: TimeRange) {
            self.text = text
            self.timeline = timeline
        }
    }

    public var words: [Word]
    /// When the caption shows.
    public var timeline: TimeRange

    public init(words: [Word], timeline: TimeRange) {
        self.words = words
        self.timeline = timeline
    }

    public var text: String { words.map(\.text).joined(separator: " ") }

    /// The word being said at a time, if any.
    public func wordIndex(at time: TimeInterval) -> Int? {
        words.lastIndex { $0.timeline.start <= time }
    }
}

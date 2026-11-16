import Foundation

/// A fix to what the transcript says: a run of words replaced by new ones (docs/decisions.md, 69).
///
/// A fix replaces the words outright. There's no idea of "heard" words anywhere a creator or Claude looks:
/// once laid over the transcript, the new words are simply the transcript's words, each with its own id and
/// times. The transcript file keeps the model's output underneath; fixes live in `edit.json`, so History and
/// Undo cover them like any other change.
///
/// Fixes are laid over the transcript in order. Each replaces words in the transcript as the fixes before it
/// left it, so fixing a fix works the same as fixing what the model wrote.
public struct WordFix: Codable, Equatable, Sendable {
    /// The words it replaces, first to last, in one transcript.
    public var replaces: ItemRange
    /// The new words, in order, with new ids. Ids are never reused.
    public var words: [Word]
    /// Whether the new words were timed against the audio. An untimed fix is one word holding all the text,
    /// spanning the words it replaced, so it cuts as a whole.
    public var isTimed: Bool

    public init(replaces: ItemRange, words: [Word], isTimed: Bool) {
        self.replaces = replaces
        self.words = words
        self.isTimed = isTimed
    }
}

/// A word placed in the audio by forced alignment, in seconds of source time (docs/decisions.md, 69).
public struct AlignedWord: Codable, Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

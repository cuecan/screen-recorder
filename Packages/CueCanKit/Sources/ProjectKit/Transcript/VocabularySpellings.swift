import Foundation

/// The vocabulary's spellings for one transcript: where FluidAudio's vocabulary boosting swapped in a term
/// (docs/decisions.md, 42). Stored beside the transcript as `transcripts/<source>.spellings.json`.
///
/// A transcript never changes once written, so a spelling sits on top of it, keyed by the ids of the words
/// it replaces. Setting new terms writes a new file; the transcript stays as it was.
public struct VocabularySpellings: Codable, Equatable, Sendable {
    /// One swap: these words read as `text`.
    public struct Spelling: Codable, Equatable, Sendable {
        public var words: ItemRange
        public var text: String

        public init(words: ItemRange, text: String) {
            self.words = words
            self.text = text
        }
    }

    public var source: SourceID
    /// The terms boosting ran with.
    public var terms: [String]
    public var spellings: [Spelling]
    public var createdAt: Date

    public init(source: SourceID, terms: [String], spellings: [Spelling], createdAt: Date = .now) {
        self.source = source
        self.terms = terms
        self.spellings = spellings
        self.createdAt = createdAt
    }
}

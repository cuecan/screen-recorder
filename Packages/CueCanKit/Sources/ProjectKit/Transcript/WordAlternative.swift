import Foundation

/// Where Apple's SpeechAnalyzer heard a run of Parakeet's words differently (docs/decisions.md, 39).
///
/// Claude cuts by Parakeet's word ids and uses the alternative for spelling: SpeechAnalyzer is often right
/// on clean speech and names, while Parakeet keeps the stumbles an editor needs. An alternative is written
/// with the transcript and never changes, like the rest of it.
public struct WordAlternative: Codable, Equatable, Sendable {
    /// The Parakeet words SpeechAnalyzer heard differently, first to last.
    public var words: ItemRange
    /// What SpeechAnalyzer heard there. Empty when it heard nothing at all.
    public var text: String

    public init(words: ItemRange, text: String) {
        self.words = words
        self.text = text
    }
}

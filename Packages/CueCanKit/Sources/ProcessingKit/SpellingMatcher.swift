import Foundation
import ProjectKit
import TranscribeKit

/// Turns a boosted reading of a source into spellings over its written transcript, keyed by word id.
///
/// Parakeet gives the same words for the same audio every time (docs/decisions.md, 42), so the words
/// boosting left alone line up with the transcript's, and each change lands on the ids of the words it replaces.
public enum SpellingMatcher {
    public static func spellings(for transcript: Transcript, boosted: [TimedWord], terms: [String]) -> VocabularySpellings {
        let words = transcript.words
        let timed = words.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
        let corrections = VocabularyCorrection.corrections(boosted.map(\.text).joined(separator: " "), to: timed)
        let spellings = corrections.compactMap { correction -> VocabularySpellings.Spelling? in
            guard !correction.words.isEmpty, correction.words.upperBound <= words.count else { return nil }
            return VocabularySpellings.Spelling(
                words: ItemRange(first: .word(words[correction.words.lowerBound].id), last: .word(words[correction.words.upperBound - 1].id)),
                text: correction.text
            )
        }
        return VocabularySpellings(source: transcript.source, terms: terms, spellings: spellings)
    }
}

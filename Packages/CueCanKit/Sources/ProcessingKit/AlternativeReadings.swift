import Foundation
import ProjectKit
import TranscribeKit

/// Where a second engine heard a transcript's words differently: SpeechAnalyzer against Parakeet
/// (docs/decisions.md, 39). Each run of Parakeet's words that SpeechAnalyzer read another way becomes one
/// alternative, by the words' positions.
///
/// The two readings are compared without case or punctuation, so "daily." and "Daily" aren't a different
/// reading. Words SpeechAnalyzer added with nothing of Parakeet's to sit on are left out: there are no ids
/// to attach them to.
public enum AlternativeReadings {
    public static func alternatives(for draft: TranscriptDraft, secondReading: [TimedWord]) -> [TranscriptDraft.DraftAlternative] {
        let words = draft.items.compactMap { item -> String? in
            if case .word(let word) = item { word.text } else { nil }
        }
        let other = secondReading.map(\.text)
        return WordDiff.changes(from: words.map(normalized), to: other.map(normalized)).compactMap { change in
            guard !change.old.isEmpty else { return nil }
            return TranscriptDraft.DraftAlternative(words: change.old, text: other[change.new].joined(separator: " "))
        }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

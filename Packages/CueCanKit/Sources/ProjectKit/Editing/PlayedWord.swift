import Foundation

/// A word occurrence on the edited timeline. Repeated source words keep their own clip occurrence.
public struct PlayedWord: Equatable, Sendable {
    /// Stable view identity for this occurrence: a source word may play in more than one clip.
    public struct OccurrenceID: Hashable, Sendable {
        public let clip: ClipID
        public let word: WordID
    }
    public let id: WordID
    public let source: SourceID
    public let clip: ClipID
    public let text: String
    public let range: TimeRange
    public let isFiller: Bool
    public var occurrenceID: OccurrenceID { .init(clip: clip, word: id) }

    /// A readable group for a zoomed-out timeline. Group identity includes the occurrence, so repeating
    /// the same source words in another clip never gives a view two children with the same identity.
    public struct Phrase: Identifiable, Equatable, Sendable {
        public let id: OccurrenceID
        public let words: ItemRange
        public let range: TimeRange
        public let text: String
    }

    /// Groups nearby occurrences within one clip. Words a spelling leaves blank remain in the selected range;
    /// consumers can still reach and restore them even though they are omitted from exported text.
    public static func phrases(_ words: [Self], maximumCharacters: Int = 120) -> [Phrase] {
        var result: [Phrase] = []
        var run: [Self] = []
        var characters = 0
        func flush() {
            guard let first = run.first, let last = run.last else { return }
            let text = run.map { $0.text.isEmpty ? "…" : $0.text }.joined(separator: " ")
            result.append(Phrase(id: first.occurrenceID, words: ItemRange(first: .word(first.id), last: .word(last.id)),
                                 range: TimeRange(start: first.range.start, end: run.map(\.range.end).max() ?? last.range.end), text: text))
            run.removeAll(keepingCapacity: true)
            characters = 0
        }
        for word in words {
            if let last = run.last,
               last.clip != word.clip || word.range.start - last.range.end >= 0.35 || characters + word.text.count + 1 > max(1, maximumCharacters) {
                flush()
            }
            run.append(word)
            characters += max(1, word.text.count) + 1
        }
        flush()
        return result
    }

    /// All played words, including fillers and words a vocabulary spelling leaves blank. Consumers choose how to show them.
    public static func project(edit: Edit, placements: [Edit.TimelinePlacement], transcripts: TranscriptIndex,
                               spellings: [SourceID: VocabularySpellings] = [:]) -> [Self] {
        var texts: [SourceID: [WordID: String]] = [:]
        return placements.flatMap { placed -> [Self] in
            let source = placed.clip.source
            guard let transcript = transcripts[source] else { return [] }
            if texts[source] == nil { texts[source] = edit.exportTexts(of: transcript, spellings: spellings[source]) }
            let played = placed.clip.playedRange
            return transcript.words.compactMap { word in
                let middle = (word.start + word.end) / 2
                guard middle >= played.start, middle < played.end else { return nil }
                let start = placed.timelineTime(ofSourceTime: max(word.start, played.start))
                let end = placed.timelineTime(ofSourceTime: min(word.end, played.end))
                return Self(id: word.id, source: source, clip: placed.clip.id, text: texts[source]?[word.id] ?? word.text,
                            range: TimeRange(start: start, end: max(start, end)), isFiller: word.isFiller)
            }
        }
    }
}

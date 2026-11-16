import Foundation
import ProjectKit

/// Turns the words the edit plays into the SRT's captions on the edited timeline, so they move with every cut
/// and go through every speed change (docs/decisions.md, 43 and 59). Nothing is burned into the picture.
///
/// A word plays if its middle falls inside a clip, so a word cut partway stays only if most of it is kept.
/// Filler words are left out. Vocabulary spellings, then the edit's own word fixes, replace the words they
/// cover. A caption breaks at the end of a sentence, at a pause, or when it's full.
public enum CaptionBuilder {
    /// How words are grouped into captions. The values are starting points (AUTHOR'S TAKE NEEDED).
    public struct Grouping: Equatable, Sendable {
        public var maximumCharacters: Int
        public var maximumWords: Int
        /// A gap between words at least this long starts a new caption.
        public var pauseBreak: TimeInterval
        /// A caption shows at least this long, unless the next one starts sooner.
        public var minimumDuration: TimeInterval

        public static let standard = Grouping(maximumCharacters: 42, maximumWords: 12, pauseBreak: 0.6, minimumDuration: 0.7)
    }

    /// The captions for an edit.
    ///
    /// - Parameter spellings: Vocabulary spellings by source, which replace the words they cover.
    public static func cues(
        edit: Edit,
        timeline: EditTimeline,
        transcripts: TranscriptIndex,
        spellings: [SourceID: VocabularySpellings] = [:],
        grouping: Grouping = .standard
    ) -> [CaptionCue] {
        group(playedWords(edit: edit, timeline: timeline, transcripts: transcripts, spellings: spellings), grouping: grouping)
    }

    /// Each played word on the timeline, in timeline order, as the exports write it.
    static func playedWords(
        edit: Edit,
        timeline: EditTimeline,
        transcripts: TranscriptIndex,
        spellings: [SourceID: VocabularySpellings]
    ) -> [CaptionCue.Word] {
        PlayedWord.project(edit: edit, placements: timeline.clips, transcripts: transcripts, spellings: spellings)
            .filter { !$0.isFiller && !$0.text.isEmpty }
            .map { CaptionCue.Word(text: $0.text, timeline: $0.range) }
    }

    static func group(_ words: [CaptionCue.Word], grouping: Grouping) -> [CaptionCue] {
        var groups: [[CaptionCue.Word]] = []
        var current: [CaptionCue.Word] = []
        for word in words {
            if let last = current.last {
                let characters = current.map(\.text.count).reduce(0, +) + current.count + word.text.count
                let endsSentence = last.text.last.map { ".?!".contains($0) } ?? false
                let pause = word.timeline.start - last.timeline.end >= grouping.pauseBreak
                let jumped = word.timeline.start < last.timeline.start
                if endsSentence || pause || jumped || characters > grouping.maximumCharacters || current.count >= grouping.maximumWords {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        var cues: [CaptionCue] = []
        for (index, words) in groups.enumerated() {
            guard let first = words.first, let last = words.last else { continue }
            var end = max(last.timeline.end, first.timeline.start + grouping.minimumDuration)
            if index + 1 < groups.count, let next = groups[index + 1].first {
                end = min(end, max(next.timeline.start, last.timeline.end))
            }
            cues.append(CaptionCue(words: words, timeline: TimeRange(start: first.timeline.start, end: end)))
        }
        return cues
    }
}

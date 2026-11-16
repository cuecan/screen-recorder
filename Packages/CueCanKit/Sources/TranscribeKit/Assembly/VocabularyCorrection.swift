import Foundation

/// Puts a corrected reading of a transcript back onto its timed words.
///
/// Vocabulary boosting hands back corrected text, not timed words. Two ways to use it:
/// - ``apply(_:to:)`` gives new timed words, for a transcript not written yet.
/// - ``corrections(_:to:)`` gives each change as the words it replaces, by position. A transcript never
///   changes once written, so a correction made later sits on top of it, keyed by those words' ids. Parakeet
///   gives the same words for the same audio every time (measured: docs/bakeoff-findings.md), so the words it
///   left alone line up with the written transcript.
public enum VocabularyCorrection {
    /// One change: the words at `words` read as `text` instead.
    public struct Correction: Sendable, Equatable {
        /// Positions in the original words. Never empty.
        public var words: Range<Int>
        /// What they read as, which can be more or fewer words, such as "passkey" for "pass key". Empty when
        /// the words weren't said at all.
        public var text: String

        public init(words: Range<Int>, text: String) {
            self.words = words
            self.text = text
        }
    }

    /// The words in `corrected` that differ from `words`, as the runs of original words they replace.
    ///
    /// A replacement can share words with the original: "Final Cut" → "Final Cut Pro" looks like an
    /// insertion to a word diff. Such a change takes in the word before it, or the word after it at the
    /// start, so it still has original word ids and a time span. Changes that then overlap are combined.
    /// With no original words, there's no id or time span to attach a correction to, so there are none.
    public static func corrections(_ corrected: String, to words: [TimedWord]) -> [Correction] {
        guard !words.isEmpty else { return [] }
        let newTexts = Self.words(in: corrected)
        var changes: [WordDiff.Change] = []
        for var change in WordDiff.changes(from: words.map(\.text), to: newTexts) {
            if change.old.isEmpty || change.new.isEmpty {
                if change.old.lowerBound > 0, change.new.lowerBound > 0 {
                    change.old = (change.old.lowerBound - 1)..<change.old.upperBound
                    change.new = (change.new.lowerBound - 1)..<change.new.upperBound
                } else if change.old.upperBound < words.count, change.new.upperBound < newTexts.count {
                    change.old = change.old.lowerBound..<(change.old.upperBound + 1)
                    change.new = change.new.lowerBound..<(change.new.upperBound + 1)
                }
            }
            if let previous = changes.last,
                previous.old.overlaps(change.old) || previous.new.overlaps(change.new)
            {
                changes[changes.count - 1] = WordDiff.Change(
                    old: min(previous.old.lowerBound, change.old.lowerBound)..<max(previous.old.upperBound, change.old.upperBound),
                    new: min(previous.new.lowerBound, change.new.lowerBound)..<max(previous.new.upperBound, change.new.upperBound)
                )
            } else {
                changes.append(change)
            }
        }
        return changes.map { change in
            Correction(words: change.old, text: newTexts[change.new].joined(separator: " "))
        }
    }

    /// The timed words with `corrected`'s changes made. Words left alone keep their times. A run that changed
    /// takes the time of the words it replaced: one for one when the counts match, such as "lateral" →
    /// "Laravel"; otherwise spread over that span by length, such as "pass key" → "passkey".
    public static func apply(_ corrected: String, to words: [TimedWord]) -> [TimedWord] {
        let corrections = corrections(corrected, to: words)
        guard !corrections.isEmpty else { return words }

        var result: [TimedWord] = []
        var position = 0
        for correction in corrections {
            result.append(contentsOf: words[position..<correction.words.lowerBound])
            result.append(contentsOf: retimed(Self.words(in: correction.text), over: Array(words[correction.words])))
            position = correction.words.upperBound
        }
        result.append(contentsOf: words[position...])
        return result
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// New words in the time of the old ones they replace, with the old ones' average confidence.
    static func retimed(_ texts: [String], over replaced: [TimedWord]) -> [TimedWord] {
        guard let first = replaced.first, let last = replaced.last, !texts.isEmpty else { return [] }
        let confidences = replaced.compactMap(\.confidence)
        let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)

        if texts.count == replaced.count {
            return zip(texts, replaced).map { text, word in
                TimedWord(text: text, start: word.start, end: word.end, confidence: confidence)
            }
        }
        let lengths = texts.map { Double(max(1, $0.count)) }
        let total = lengths.reduce(0, +)
        let span = last.end - first.start
        var start = first.start
        var result: [TimedWord] = []
        for (index, (text, length)) in zip(texts, lengths).enumerated() {
            let end = index == texts.count - 1 ? last.end : start + span * length / total
            result.append(TimedWord(text: text, start: start, end: end, confidence: confidence))
            start = end
        }
        return result
    }
}

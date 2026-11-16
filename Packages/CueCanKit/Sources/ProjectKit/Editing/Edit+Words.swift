import Foundation

/// Fixing what the transcript says (`set_word_text`, Fix Text…; docs/decisions.md, 69). A fix replaces the
/// words: their new ids and times are the transcript's from then on.
extension Edit {
    /// Replaces a run of words with `text`.
    ///
    /// With `timings`, from aligning the text against the audio, each aligned word becomes a word of its own.
    /// Without, the fix is one word holding all the text over the time of the words it replaces, so it cuts
    /// as a whole. New word ids start at `nextWordNumber`, which moves past them: ids are project-wide and
    /// never reused, so the number lives in `project.json`, not here.
    ///
    /// - Parameter transcripts: The transcripts with this edit's fixes already laid over them.
    @discardableResult
    public mutating func fixWords(
        _ range: ItemRange,
        as text: String,
        timings: [AlignedWord]?,
        transcripts: TranscriptIndex,
        nextWordNumber: inout Int
    ) throws(EditError) -> WordFix {
        let transcript = try transcripts.transcript(containing: range)
        let indices = try CutPointSnapper(transcript: transcript).indices(of: range)
        guard case .word = range.first, case .word = range.last else { throw .wordsNotWords(range) }
        let text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { throw .emptyFix(range) }
        let replaced = transcript.items[indices].compactMap { item -> Word? in if case .word(let word) = item { word } else { nil } }
        guard let first = replaced.first, let last = replaced.last else { throw .wordsNotWords(range) }

        func makeWord(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> Word {
            defer { nextWordNumber += 1 }
            return Word(id: WordID(number: nextWordNumber), text: text, start: start, end: max(start, end))
        }
        let fix: WordFix
        if let timings, !timings.isEmpty, timings.map(\.text).joined(separator: " ") == text {
            fix = WordFix(replaces: range, words: timings.map { makeWord($0.text, $0.start, $0.end) }, isTimed: true)
        } else {
            fix = WordFix(replaces: range, words: [makeWord(text, first.start, last.end)], isTimed: false)
        }
        // A fix retires ids. Keep an overlay's existing placement when one of its anchors is retired,
        // including a silence swallowed by the new timings. Source-time anchors still follow every cut.
        if let fixed = transcript.applying(fix) {
            for index in overlays.indices {
                guard case .words(let anchor) = overlays[index].over,
                      transcript.contains(anchor.first), transcript.contains(anchor.last),
                      !fixed.contains(anchor.first) || !fixed.contains(anchor.last),
                      let time = try? CutPointSnapper(transcript: transcript).timeRange(for: anchor)
                else { continue }
                overlays[index].over = .time(source: transcript.source, range: time)
            }
        }
        fixes.append(fix)
        return fix
    }

    /// Each word's text for the exports and the editor, with the vocabulary's spellings (42) laid on. Under a
    /// spelling, the first word carries the text and the rest carry nothing. Fixes need nothing here: they're
    /// already the transcript's words.
    public func exportTexts(of transcript: Transcript, spellings: VocabularySpellings? = nil) -> [WordID: String] {
        let words = transcript.words
        var texts = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0.text) })
        let positions = Dictionary(uniqueKeysWithValues: words.enumerated().map { ($1.id, $0) })
        for spelling in spellings?.spellings ?? [] {
            guard case .word(let first) = spelling.words.first, case .word(let last) = spelling.words.last,
                let from = positions[first], let to = positions[last], from <= to
            else { continue }
            for index in from...to { texts[words[index].id] = index == from ? spelling.text : "" }
        }
        return texts
    }
}

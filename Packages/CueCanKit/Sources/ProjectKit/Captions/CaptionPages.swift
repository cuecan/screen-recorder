import Foundation

/// One caption word on the edited timeline.
public struct CaptionWord: Equatable, Sendable {
    public var id: WordID
    /// As drawn: capitals and punctuation already applied by the style.
    public var text: String
    /// When it's said on the edited timeline, moved by the lead if asked.
    public var timeline: TimeRange
    public var clip: ClipID
    public var isEmphasised: Bool
    /// The creator or Claude asked for a line to start here.
    public var startsLine: Bool

    public init(id: WordID, text: String, timeline: TimeRange, clip: ClipID, isEmphasised: Bool = false, startsLine: Bool = false) {
        self.id = id
        self.text = text
        self.timeline = timeline
        self.clip = clip
        self.isEmphasised = isEmphasised
        self.startsLine = startsLine
    }
}

/// The words on screen together, and when.
public struct CaptionPage: Equatable, Sendable {
    public var words: [CaptionWord]
    /// From the first word's start until a moment after the last word ends, never into the next page or past
    /// its clip.
    public var show: TimeRange

    public init(words: [CaptionWord], show: TimeRange) {
        self.words = words
        self.show = show
    }

    /// The word being said at a time: the last that has started, held until the next starts, so the mark never
    /// flickers off between words. Nil before the first.
    public func spokenIndex(at time: TimeInterval) -> Int? {
        words.lastIndex { $0.timeline.start <= time }
    }

    /// A word's turn: from its start to the next word's start, or to the page's end.
    public func turn(of index: Int) -> TimeRange {
        TimeRange(start: words[index].timeline.start, end: index + 1 < words.count ? words[index + 1].timeline.start : show.end)
    }
}

/// Puts the words an edit plays into pages (docs/design.md, "Captions").
///
/// A page breaks at the end of a sentence, at a clause once it has two words, at a pause, at a cut, at the
/// style's word and character limits and at a forced break past its lines. Pauses are what keep a take
/// Parakeet gave no punctuation readable.
public enum CaptionPaginator {
    /// A gap between words at least this long starts a new page. A starting value (AUTHOR'S TAKE NEEDED).
    public static let pauseBreak: TimeInterval = 0.3
    /// How long a page stays after its last word ends. A starting value (AUTHOR'S TAKE NEEDED).
    public static let hold: TimeInterval = 0.4
    /// A page runs on to the next one when the gap between them would be shorter than this, so the text doesn't
    /// blink off and on.
    public static let bridge: TimeInterval = 0.25

    /// Pages for words in timeline order.
    ///
    /// - Parameter clipEnds: Where each clip ends on the timeline: a page never outlasts its clip.
    public static func pages(_ words: [CaptionWord], style: CaptionStyle, clipEnds: [ClipID: TimeInterval] = [:]) -> [CaptionPage] {
        var groups: [[CaptionWord]] = []
        var current: [CaptionWord] = []
        var characters = 0
        var lines = 1
        for var word in words {
            if let last = current.last {
                let ending = last.text.last
                let endsSentence = ending.map { ".?!…".contains($0) } ?? false
                let endsClause = ending.map { ",;:—".contains($0) } ?? false
                let pause = word.timeline.start - last.timeline.end >= pauseBreak
                let cut = word.clip != last.clip || word.timeline.start < last.timeline.start
                let full = current.count >= style.words.atOnce || characters + 1 + word.text.count > style.words.characters
                let tooManyLines = word.startsLine && lines >= style.words.lines
                if endsSentence || (endsClause && current.count >= 2) || pause || cut || full || tooManyLines {
                    groups.append(current)
                    current = []
                    characters = 0
                    lines = 1
                }
            }
            if current.isEmpty { word.startsLine = false }
            if word.startsLine { lines += 1 }
            characters += (current.isEmpty ? 0 : 1) + word.text.count
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        var pages: [CaptionPage] = []
        for (index, words) in groups.enumerated() {
            let start = words[0].timeline.start
            var end = (words.map(\.timeline.end).max() ?? start) + hold
            if let clipEnd = clipEnds[words[words.count - 1].clip] { end = min(end, clipEnd) }
            if index + 1 < groups.count {
                let next = groups[index + 1][0]
                let sameClip = next.clip == words[words.count - 1].clip
                if next.timeline.start - end < bridge, sameClip { end = next.timeline.start }
                end = min(end, next.timeline.start)
            }
            pages.append(CaptionPage(words: words, show: TimeRange(start: start, end: max(start, end))))
        }
        return pages
    }

    /// A word as drawn: trimmed, without commas and full stops unless the style keeps them (a question or
    /// exclamation mark stays), in capitals if the style says. Pages still break on the original punctuation.
    public static func displayText(_ text: String, style: CaptionStyle) -> String {
        var shown = text.trimmingCharacters(in: .whitespaces)
        if !style.words.keepsPunctuation {
            while let last = shown.last, ",.;:…".contains(last), shown.count > 1 { shown.removeLast() }
        }
        return style.words.uppercase ? shown.uppercased() : shown
    }

    /// The words an edit plays in clips that show captions in `output`, ready to page: fixes already laid over the transcript, fillers and words a
    /// vocabulary spelling blanks left out (as in the SRT). Text is kept as the transcript has it; pages break
    /// on its punctuation and ``displayText(_:style:)`` is applied when drawing.
    public static func words(edit: Edit, output: OutputShape, placements: [Edit.TimelinePlacement], transcripts: TranscriptIndex,
                             spellings: [SourceID: VocabularySpellings] = [:], lead: TimeInterval = 0) -> [CaptionWord] {
        let emphasis = Set(edit.captions.emphasis)
        let breaks = Set(edit.captions.lineBreaks)
        let shown = placements.filter { $0.clip.look.captions }
        let ranges = Dictionary(uniqueKeysWithValues: shown.map { ($0.clip.id, $0.timeline) })
        return PlayedWord.project(edit: edit, placements: shown, transcripts: transcripts, spellings: spellings)
            .filter { !$0.isFiller && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { word in
                guard let range = ranges[word.clip] else { return nil }
                let shifted = TimeRange(start: max(range.start, word.range.start - lead), end: min(range.end, word.range.end - lead))
                guard shifted.end > shifted.start else { return nil }
                return CaptionWord(id: word.id, text: word.text, timeline: shifted,
                                   clip: word.clip, isEmphasised: emphasis.contains(word.id), startsLine: breaks.contains(word.id))
            }
    }
}

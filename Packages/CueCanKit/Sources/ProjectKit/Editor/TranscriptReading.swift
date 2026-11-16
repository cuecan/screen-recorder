import Foundation

/// The transcript as the inspector shows it (docs/ui.md, "The transcript in the inspector"; docs/decisions.md,
/// 69): paragraphs of words with the silences worth seeing, and what was in front on screen beside them.
///
/// Only the words, where they were said, and the silence after them: a silence of ``pauseLength`` or
/// more shows as a chip after the words before it, and one of ``longSilence`` or more as a block of its own,
/// with the words after it starting a new paragraph. A paragraph also starts where another app came to the
/// front, or another recording starts.
public struct TranscriptReading: Equatable, Sendable {
    /// What the transcript shows: Edit only what plays, so it reads as the finished video; Full
    /// everything recorded, with what was cut marked.
    public enum Mode: String, CaseIterable, Sendable {
        case edit, full
    }

    /// A word or a silence worth showing.
    public struct Token: Identifiable, Equatable, Sendable {
        /// The item, and in Edit the clip playing it: a word can play in more than one clip.
        public struct ID: Hashable, Sendable {
            public let clip: ClipID?
            public let item: TranscriptItemID
        }

        public enum Kind: Equatable, Sendable {
            case word(String)
            /// A silence, with how long it plays (Edit) or lasts (Full), in seconds.
            case silence(TimeInterval)
        }

        public let id: ID
        public let source: SourceID
        public let kind: Kind
        /// Where it is in the recording, in source time.
        public let sourceRange: TimeRange
        /// Where it plays in the edit; nil when it's cut.
        public let timeline: TimeRange?
        /// For a word from a fix that couldn't be timed: it holds a whole fix and cuts as one.
        public let isUntimed: Bool
        /// Where another window of the same app came to the front, the window it was: a tick on the rail.
        public internal(set) var windowChange: ScreenFront?

        public var item: TranscriptItemID { id.item }
        public var isCut: Bool { timeline == nil }
        public var text: String? { if case .word(let text) = kind { text } else { nil } }
        public var silenceLength: TimeInterval? { if case .silence(let length) = kind { length } else { nil } }
    }

    /// Words said one after another with the same app in front.
    public struct Paragraph: Identifiable, Equatable, Sendable {
        public var id: Token.ID { tokens[0].id }
        public internal(set) var tokens: [Token]
        /// What was in front when it starts: the icon at the top of the rail.
        public let front: ScreenFront?
    }

    public enum Block: Identifiable, Equatable, Sendable {
        case paragraph(Paragraph)
        /// A long silence, across the text.
        case silence(Token)

        public var id: Token.ID {
            switch self {
            case .paragraph(let paragraph): paragraph.id
            case .silence(let token): token.id
            }
        }
    }

    /// A silence this long or more shows as a chip after the words before it. Claude's call (as asked: "about a
    /// second").
    public static let pauseLength: TimeInterval = 1
    /// A silence this long or more gets a block of its own. Claude's call (as asked: "long sections of silence").
    public static let longSilence: TimeInterval = 4
    /// A paragraph this many words long breaks at the next sentence's end, so the text stays readable.
    public static let paragraphWords = 60

    public let mode: Mode
    public let blocks: [Block]

    /// Every token, in order.
    public var tokens: [Token] {
        blocks.flatMap { block -> [Token] in
            switch block {
            case .paragraph(let paragraph): paragraph.tokens
            case .silence(let token): [token]
            }
        }
    }

    /// The position of a token, in ``tokens``.
    public func index(of id: Token.ID) -> Int? {
        tokens.firstIndex { $0.id == id }
    }

    /// The runs of items from one token through another, either way round, for cutting and putting back:
    /// one run for each stretch of one recording played in order, since a run is named by its first and
    /// last item.
    public func itemRanges(from first: Token.ID, through last: Token.ID) -> [ItemRange] {
        let tokens = tokens
        guard let from = tokens.firstIndex(where: { $0.id == first }), let to = tokens.firstIndex(where: { $0.id == last }) else { return [] }
        var runs: [(source: SourceID, clip: ClipID?, first: Token, last: Token)] = []
        for token in tokens[min(from, to)...max(from, to)] {
            if let run = runs.last, run.source == token.source, run.clip == token.id.clip, run.last.sourceRange.start <= token.sourceRange.start {
                runs[runs.count - 1].last = token
            } else {
                runs.append((token.source, token.id.clip, token, token))
            }
        }
        return runs.map { ItemRange(first: $0.first.item, last: $0.last.item) }
    }

    /// The words from one token through another, trimmed to words, when they're one run of one recording:
    /// what Fix Text… replaces.
    public func wordRange(from first: Token.ID, through last: Token.ID) -> ItemRange? {
        let ranges = itemRanges(from: first, through: last)
        guard ranges.count == 1, let from = index(of: first), let to = index(of: last) else { return nil }
        let words = tokens[min(from, to)...max(from, to)].filter { $0.text != nil }
        guard let start = words.first, let end = words.last else { return nil }
        return ItemRange(first: start.item, last: end.item)
    }

    /// Lays out the transcript.
    ///
    /// - Parameters:
    ///   - placements: The edit's main track on the timeline.
    ///   - sources: The recordings in the project's order, for Full.
    ///   - texts: Each source's word texts, with the vocabulary's spellings (``Edit/exportTexts(of:spellings:)``).
    ///   - fronts: Each source's settled screen fronts (``ScreenFront/settled(from:until:settlingTime:)``).
    public init(
        mode: Mode,
        placements: [Edit.TimelinePlacement],
        sources: [SourceID],
        transcripts: TranscriptIndex,
        texts: [SourceID: [WordID: String]] = [:],
        fronts: [SourceID: [ScreenFront]] = [:]
    ) {
        self.mode = mode
        var builder = Builder(fronts: fronts)
        switch mode {
        case .edit:
            for placed in placements {
                guard let transcript = transcripts[placed.clip.source] else { continue }
                let played = placed.clip.playedRange
                for item in transcript.items {
                    switch item {
                    case .word(let word):
                        let middle = (word.start + word.end) / 2
                        guard middle >= played.start, middle < played.end else { continue }
                        builder.add(Self.word(word, clip: placed.clip.id, source: transcript.source, texts: texts,
                                              timeline: placed.timeline(of: word.start, word.end), transcripts: transcripts))
                    case .silence(let silence):
                        let start = max(silence.start, played.start), end = min(silence.end, played.end)
                        guard end > start else { continue }
                        builder.add(Token(id: .init(clip: placed.clip.id, item: item.id), source: transcript.source,
                                          kind: .silence((end - start) / placed.clip.speed.rate),
                                          sourceRange: TimeRange(start: start, end: end),
                                          timeline: placed.timeline(of: start, end), isUntimed: false))
                    }
                }
            }
        case .full:
            for source in sources {
                guard let transcript = transcripts[source] else { continue }
                let clips = placements.filter { $0.clip.source == source }
                func playing(_ start: TimeInterval, _ end: TimeInterval) -> TimeRange? {
                    let middle = (start + end) / 2
                    return clips.first { $0.clip.playedRange.start <= middle && middle < $0.clip.playedRange.end }
                        .map { $0.timeline(of: start, end) }
                }
                for item in transcript.items {
                    switch item {
                    case .word(let word):
                        builder.add(Self.word(word, clip: nil, source: source, texts: texts,
                                              timeline: playing(word.start, word.end), transcripts: transcripts))
                    case .silence(let silence):
                        builder.add(Token(id: .init(clip: nil, item: item.id), source: source, kind: .silence(silence.duration),
                                          sourceRange: TimeRange(start: silence.start, end: silence.end),
                                          timeline: playing(silence.start, silence.end), isUntimed: false))
                    }
                }
            }
        }
        builder.flush()
        blocks = builder.blocks
    }

    private static func word(_ word: Word, clip: ClipID?, source: SourceID, texts: [SourceID: [WordID: String]],
                             timeline: TimeRange?, transcripts: TranscriptIndex) -> Token {
        Token(id: .init(clip: clip, item: .word(word.id)), source: source, kind: .word(texts[source]?[word.id] ?? word.text),
              sourceRange: TimeRange(start: word.start, end: word.end), timeline: timeline,
              isUntimed: transcripts.untimedWords.contains(word.id))
    }

    /// Gathers tokens into paragraphs and long silences.
    private struct Builder {
        let fronts: [SourceID: [ScreenFront]]
        var blocks: [Block] = []
        var tokens: [Token] = []
        var paragraphFront: ScreenFront?
        var lastFront: ScreenFront?
        var words = 0

        mutating func add(_ token: Token) {
            switch token.kind {
            case .silence(let length):
                if length >= TranscriptReading.longSilence {
                    flush()
                    blocks.append(.silence(token))
                } else if length >= TranscriptReading.pauseLength, !tokens.isEmpty {
                    tokens.append(token)
                }
            case .word(let text):
                let front = fronts[token.source].flatMap { ScreenFront.front(at: token.sourceRange.start, in: $0) }
                if let previous = tokens.last(where: { $0.text != nil }) {
                    let newApp = front.map { front in lastFront.map { !$0.isSameApp(as: front) } ?? true } ?? false
                    let endsSentence = previous.text.map { [".", "?", "!"].contains($0.last) } ?? false
                    if previous.source != token.source || newApp || (words >= TranscriptReading.paragraphWords && endsSentence) {
                        flush()
                    }
                }
                var token = token
                if tokens.isEmpty {
                    paragraphFront = front
                } else if let front, let lastFront, !front.isSameWindow(as: lastFront) {
                    token.windowChange = front
                }
                lastFront = front ?? lastFront
                tokens.append(token)
                words += text.isEmpty ? 0 : 1
            }
        }

        mutating func flush() {
            if !tokens.isEmpty { blocks.append(.paragraph(Paragraph(tokens: tokens, front: paragraphFront))) }
            tokens = []
            words = 0
        }
    }
}

extension Edit.TimelinePlacement {
    /// Where a stretch of this clip's source plays, clamped to what the clip plays.
    func timeline(of start: TimeInterval, _ end: TimeInterval) -> TimeRange {
        let played = clip.playedRange
        let from = timelineTime(ofSourceTime: max(start, played.start))
        return TimeRange(start: from, end: max(from, timelineTime(ofSourceTime: min(end, played.end))))
    }
}

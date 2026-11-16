import Foundation

/// A transcript before it has ids: what a transcription pipeline and a silence detector produce.
///
/// ``ProjectFolder/addTranscript(_:for:)`` turns a draft into a ``Transcript``, giving each word and
/// silence the next project-wide id, so ids never collide across sources.
public struct TranscriptDraft: Equatable, Sendable {
    /// A word before it has an id.
    public struct DraftWord: Equatable, Sendable {
        public var text: String
        public var start: TimeInterval
        public var end: TimeInterval
        public var confidence: Double?
        public var isFiller: Bool

        public init(
            text: String,
            start: TimeInterval,
            end: TimeInterval,
            confidence: Double? = nil,
            isFiller: Bool = false
        ) {
            self.text = text
            self.start = start
            self.end = end
            self.confidence = confidence
            self.isFiller = isFiller
        }
    }

    /// A word or a silence, in spoken order.
    public enum DraftItem: Equatable, Sendable {
        case word(DraftWord)
        case silence(start: TimeInterval, end: TimeInterval)
    }

    /// Another engine's reading of a run of words, by their positions among the draft's words (not its
    /// items), such as SpeechAnalyzer's (``WordAlternative``).
    public struct DraftAlternative: Equatable, Sendable {
        public var words: Range<Int>
        public var text: String

        public init(words: Range<Int>, text: String) {
            self.words = words
            self.text = text
        }
    }

    public var engine: String
    public var silenceDetector: String
    public var language: String?
    /// The length of the audio that was transcribed, in seconds.
    public var audioDuration: TimeInterval
    public var items: [DraftItem]
    public var alternatives: [DraftAlternative]

    public init(
        engine: String,
        silenceDetector: String,
        language: String?,
        audioDuration: TimeInterval,
        items: [DraftItem],
        alternatives: [DraftAlternative] = []
    ) {
        self.engine = engine
        self.silenceDetector = silenceDetector
        self.language = language
        self.audioDuration = audioDuration
        self.items = items
        self.alternatives = alternatives
    }

    /// Gives every item an id, starting from the given numbers, and returns the transcript with the
    /// numbers to use next.
    public func assigningIDs(
        source: SourceID,
        firstWordNumber: Int,
        firstSilenceNumber: Int,
        createdAt: Date = .now
    ) -> (transcript: Transcript, nextWordNumber: Int, nextSilenceNumber: Int) {
        var wordNumber = firstWordNumber
        var silenceNumber = firstSilenceNumber
        let items = items.map { item -> TranscriptItem in
            switch item {
            case .word(let draft):
                defer { wordNumber += 1 }
                return .word(
                    Word(
                        id: WordID(number: wordNumber),
                        text: draft.text,
                        start: draft.start,
                        end: draft.end,
                        confidence: draft.confidence,
                        isFiller: draft.isFiller
                    )
                )
            case .silence(let start, let end):
                defer { silenceNumber += 1 }
                return .silence(Silence(id: SilenceID(number: silenceNumber), start: start, end: end))
            }
        }
        let wordIDs = items.compactMap { item -> TranscriptItemID? in
            if case .word(let word) = item { .word(word.id) } else { nil }
        }
        let alternatives = alternatives.compactMap { alternative -> WordAlternative? in
            guard !alternative.words.isEmpty, alternative.words.lowerBound >= 0,
                alternative.words.upperBound <= wordIDs.count
            else { return nil }
            return WordAlternative(
                words: ItemRange(first: wordIDs[alternative.words.lowerBound], last: wordIDs[alternative.words.upperBound - 1]),
                text: alternative.text
            )
        }
        let transcript = Transcript(
            source: source,
            engine: engine,
            silenceDetector: silenceDetector,
            language: language,
            createdAt: createdAt,
            audioDuration: audioDuration,
            items: items,
            alternatives: alternatives
        )
        return (transcript, wordNumber, silenceNumber)
    }
}

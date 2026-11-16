import Foundation

/// One source's transcript: every word and every real silence, each with a stable id and its times.
///
/// Transcripts never change once written. The edit is ranges over them, so Claude can always see what was
/// removed. Times are in seconds of source time.
///
/// ``items`` holds the words and silences in the order they're spoken. A silence comes from the audio
/// (an energy or voice-activity detector), not from gaps between word timestamps, which is what makes
/// it a safe place to cut.
public struct Transcript: Codable, Equatable, Sendable {
    /// The format version of a transcript file.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var source: SourceID
    /// Which pipeline wrote the words and placed them, such as `parakeet-tdt-v3`.
    public var engine: String
    /// How the silences were found, such as `energy` or `apple-speechdetector`.
    public var silenceDetector: String
    /// The language as a BCP 47 code, such as `en`, when known.
    public var language: String?
    public var createdAt: Date
    /// The length of the audio that was transcribed, in seconds.
    public var audioDuration: TimeInterval
    /// Words and silences in spoken order.
    public var items: [TranscriptItem]
    /// Runs of words that look like an earlier attempt at what follows. Marked only, never cut automatically.
    public var retakes: [Retake]
    /// Where Apple's SpeechAnalyzer heard Parakeet's words differently (``WordAlternative``).
    public var alternatives: [WordAlternative]

    public init(
        source: SourceID,
        engine: String,
        silenceDetector: String,
        language: String?,
        createdAt: Date = .now,
        audioDuration: TimeInterval,
        items: [TranscriptItem],
        retakes: [Retake] = [],
        alternatives: [WordAlternative] = []
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.source = source
        self.engine = engine
        self.silenceDetector = silenceDetector
        self.language = language
        self.createdAt = createdAt
        self.audioDuration = audioDuration
        self.items = items
        self.retakes = retakes
        self.alternatives = alternatives
    }

    /// All the words, in order.
    public var words: [Word] {
        items.compactMap { if case .word(let word) = $0 { word } else { nil } }
    }

    /// All the silences, in order.
    public var silences: [Silence] {
        items.compactMap { if case .silence(let silence) = $0 { silence } else { nil } }
    }

    /// The position of an item in ``items``, if it's in this transcript.
    public func index(of id: TranscriptItemID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// Whether an item is in this transcript.
    public func contains(_ id: TranscriptItemID) -> Bool {
        index(of: id) != nil
    }

    /// The words as plain text, separated by spaces.
    public var text: String {
        words.map(\.text).joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, source, engine, silenceDetector, language, createdAt, audioDuration, items, retakes
        case alternatives
    }

}

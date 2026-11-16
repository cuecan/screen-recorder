import Foundation

/// A word or a silence in a transcript.
///
/// Encoded flat, with a `type` field, so a transcript file reads as one list in spoken order:
/// `{"type": "word", "id": "w_12", "text": "Hello", "start": 1.02, "end": 1.31}`.
public enum TranscriptItem: Codable, Equatable, Sendable {
    case word(Word)
    case silence(Silence)

    public var id: TranscriptItemID {
        switch self {
        case .word(let word): .word(word.id)
        case .silence(let silence): .silence(silence.id)
        }
    }

    public var start: TimeInterval {
        switch self {
        case .word(let word): word.start
        case .silence(let silence): silence.start
        }
    }

    public var end: TimeInterval {
        switch self {
        case .word(let word): word.end
        case .silence(let silence): silence.end
        }
    }

    public var isSilence: Bool {
        if case .silence = self { true } else { false }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ItemType: String, Codable {
        case word
        case silence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ItemType.self, forKey: .type) {
        case .word: self = .word(try Word(from: decoder))
        case .silence: self = .silence(try Silence(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .word(let word):
            try container.encode(ItemType.word, forKey: .type)
            try word.encode(to: encoder)
        case .silence(let silence):
            try container.encode(ItemType.silence, forKey: .type)
            try silence.encode(to: encoder)
        }
    }
}

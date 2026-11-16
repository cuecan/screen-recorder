import Foundation

/// A word or a silence: one item of a transcript, the unit Claude cuts and keeps by.
public enum TranscriptItemID: Hashable, Sendable, Codable, CustomStringConvertible, LosslessStringConvertible {
    case word(WordID)
    case silence(SilenceID)

    public var description: String {
        switch self {
        case .word(let id): id.description
        case .silence(let id): id.description
        }
    }

    /// Parses `w_104` or `s_12`.
    public init?(_ description: String) {
        if let word = WordID(description) {
            self = .word(word)
        } else if let silence = SilenceID(description) {
            self = .silence(silence)
        } else {
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let id = Self(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(text)\" isn't a word or silence id. Expected w_<number> or s_<number>."
            )
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

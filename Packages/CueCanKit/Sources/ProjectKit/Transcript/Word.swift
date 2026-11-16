import Foundation

/// A spoken word, with its id and its aligned times in source time.
public struct Word: Codable, Equatable, Sendable, Identifiable {
    public let id: WordID
    /// The word as the model wrote it, with any punctuation attached ("Hello,").
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    /// The model's confidence from 0 to 1, when it gives one.
    public var confidence: Double?
    /// Whether this is a filler such as "um". Marked only, never cut automatically.
    public var isFiller: Bool

    public init(
        id: WordID,
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double? = nil,
        isFiller: Bool = false
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
        self.isFiller = isFiller
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, start, end, confidence, isFiller
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(WordID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        isFiller = try container.decodeIfPresent(Bool.self, forKey: .isFiller) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        // Only fillers carry the flag, which keeps transcript files short.
        if isFiller {
            try container.encode(true, forKey: .isFiller)
        }
    }
}

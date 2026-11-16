import Foundation

/// Splits a word into the timing model's pieces, as its SentencePiece tokenizer does. The model's
/// vocabulary is a byte-pair one: a word starts as single characters, and the two neighbours whose joined
/// piece the model learned earliest are joined, again and again, until no neighbours make a piece.
///
/// The timing model places pieces, not words (``WordTimer``), so a word has to be cut exactly the way the
/// model was trained to see it: cut any other way, its pieces match nothing in the audio and it's placed
/// almost at random. The pieces come from the model's own vocabulary file, `vocab.json`, which lists them in
/// the order they were learned: a piece earlier in the list is an earlier merge.
public struct PieceTokenizer: Sendable {
    /// SentencePiece's mark for the start of a word.
    public static let wordStart: Character = "\u{2581}"

    private let ids: [String: Int]
    private let scores: [Float]
    /// The id that stands for anything the model has no piece for. A word that needs it can't be placed.
    public let unknown: Int
    /// The id the model uses for "no piece here".
    public let blank: Int

    public init(pieces: [String], scores: [Float], unknown: Int, blank: Int) {
        var ids: [String: Int] = [:]
        for (id, piece) in pieces.enumerated() where id != unknown {
            ids[piece] = id
        }
        self.ids = ids
        self.scores = scores
        self.unknown = unknown
        self.blank = blank
    }

    /// From the model's vocabulary: its pieces in id order. The marks at the front (`<unk>`, `<ev:breath>` and
    /// the like) aren't pieces of words and are never made by joining; blank is the id after the last piece.
    public init(vocabulary: [String]) {
        var ids: [String: Int] = [:]
        for (id, piece) in vocabulary.enumerated() where !Self.isMark(piece) { ids[piece] = id }
        self.ids = ids
        scores = vocabulary.indices.map { -Float($0) }
        unknown = vocabulary.firstIndex(of: "<unk>") ?? 0
        blank = vocabulary.count
    }

    private static func isMark(_ piece: String) -> Bool {
        piece.count > 2 && piece.hasPrefix("<") && piece.hasSuffix(">")
    }

    /// Reads `vocab.json`: a list of the pieces.
    public init(contentsOf url: URL) throws {
        let vocabulary = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        guard vocabulary.count > 1 else { throw CocoaError(.fileReadCorruptFile) }
        self.init(vocabulary: vocabulary)
    }

    /// The word's pieces, or nil when part of it has no piece: a word with a character the model never saw.
    public func encode(_ word: String) -> [Int]? {
        let text = String(Self.wordStart) + word.precomposedStringWithCompatibilityMapping
        var symbols = text.unicodeScalars.map { String($0) }
        guard symbols.count > 1 else { return nil }
        while symbols.count > 1 {
            // The neighbours whose joined piece has the highest score; the leftmost of equals.
            var best: (index: Int, score: Float)?
            for index in 0..<(symbols.count - 1) {
                guard let id = ids[symbols[index] + symbols[index + 1]] else { continue }
                if best == nil || scores[id] > (best?.score ?? -.infinity) { best = (index, scores[id]) }
            }
            guard let best else { break }
            symbols[best.index] += symbols[best.index + 1]
            symbols.remove(at: best.index + 1)
        }
        var pieces: [Int] = []
        for symbol in symbols {
            guard let id = ids[symbol] else { return nil }
            pieces.append(id)
        }
        return pieces
    }
}

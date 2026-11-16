import Foundation
import Testing
@testable import TranscribeKit

/// The timing model's word-piece tokenizer (docs/decisions.md, 95).
struct PieceTokenizerTests {
    @Test func neighboursJoinInTheOrderTheModelLearnedThem() {
        // Scores as SentencePiece's byte-pair models have them: the earlier the merge, the higher.
        let pieces = ["<unk>", "\u{2581}", "s", "e", "\u{2581}s", "ee", "\u{2581}see", "\u{2581}se", "a"]
        let scores: [Float] = [0, -1, -2, -3, -10, -20, -30, -15, -4]
        let tokenizer = PieceTokenizer(pieces: pieces, scores: scores, unknown: 0, blank: pieces.count)
        // "▁s" joins first, then "▁se" (earlier than "ee"), then "▁see".
        #expect(tokenizer.encode("see") == [6])
        #expect(tokenizer.encode("sea") == [7, 8])
        #expect(tokenizer.encode("a") == [1, 8])
        #expect(tokenizer.encode("sex") == nil, "A character the model has no piece for can't be placed.")
        #expect(tokenizer.encode("") == nil)
    }

    @Test func aVocabularyListGivesTheMergeOrderAndItsMarksAreNeverPieces() {
        let tokenizer = PieceTokenizer(vocabulary: ["<unk>", "<ev:breath>", "\u{2581}", "a", "<", ">", "\u{2581}a", "a>"])
        #expect(tokenizer.unknown == 0 && tokenizer.blank == 8)
        #expect(tokenizer.encode("a") == [6])
        // "▁a" was learned before "a>", so it joins first and "a>" never forms.
        #expect(tokenizer.encode("a>") == [6, 5])
        #expect(tokenizer.encode("<unk>") == nil, "A mark's letters aren't in this little vocabulary, and the mark itself is never made.")
    }

    /// Against the real tokenizer's own output (exported with SentencePiece), where the model is
    /// installed. The same check passed on all 352 different words of four transcripts.
    @Test func aFewRealWordsCutAsSentencePieceCutThem() throws {
        guard WordTimer.isInstalled else { return }
        let tokenizer = try PieceTokenizer(contentsOf: WordTimer.directory.appending(path: "vocab.json"))
        let expected: [(String, [Int])] = [("Okay,", [944, 3857, 18187]), ("so,", [1550, 18187]), ("um,", [793, 18187]), ("let's", [7582, 19010, 18279]), ("Laravel", [1414, 1057, 5451]), ("passkeys", [1332, 2697, 1696]), ("WebAuthn", [1327, 1847, 19261, 615, 4638]), ("CSRF", [1004, 19246, 19794, 19548]), ("FCPXML", [1658, 19295, 19268, 20837, 19248, 19525]), ("SwiftUI", [567, 18607, 1754, 18265, 19433, 19131]), ("Claude", [1004, 185, 9604]), ("don't", [4914, 19010, 18265]), ("here's", [196, 1356, 19010, 18279]), ("fingerprint,", [201, 454, 53, 17466, 18265, 18187]), ("Nemotron.", [6648, 316, 949, 111, 18198]), ("timings", [5020, 6023]), ("4-bit", [18183, 20105, 18309, 14718]), ("30", [18183, 20024, 19490]), ("seconds", [9170, 2539, 18279]), ("résumé", [12810, 319, 18747]), ("it.", [906, 18198]), ("I'm", [434, 19010, 18481]), ("gonna", [218, 6868]), ("transcription.", [443, 1470, 18448, 179, 18577, 968, 18198]), ("MCP", [1288, 19295, 19268]), ("the", [150]), ("a", [65]), ("Parakeet", [6444, 106, 7370]), ("versus", [1194, 15494]), ("1Password", [18183, 19603, 19268, 7855, 18607, 3940]), ("see", [2061]), ("order", [2679, 461]), ("lines", [119, 16241])]
        for (word, ids) in expected { #expect(tokenizer.encode(word) == ids, "\(word)") }
    }
}

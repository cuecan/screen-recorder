import FluidAudio
import Foundation
import Testing
@testable import TranscribeKit

/// Grouping Parakeet's sub-word tokens into words, without loading the model.
@Suite struct ParakeetWordsTests {
    func token(_ text: String, _ start: Double, _ end: Double, _ confidence: Float = 0.9) -> TokenTiming {
        TokenTiming(token: text, tokenId: 0, startTime: start, endTime: end, confidence: confidence)
    }

    @Test func subWordTokensJoinIntoWords() {
        let words = ParakeetEngine.words(from: [
            token("▁Hel", 0.0, 0.1, 0.8), token("lo", 0.1, 0.3, 1.0),
            token("▁there", 0.4, 0.7),
            token(".", 0.7, 0.72),
        ])
        #expect(words.map(\.text) == ["Hello", "there."])
        #expect(words[0].start == 0 && words[0].end == 0.3)
        #expect(abs((words[0].confidence ?? 0) - 0.9) < 1e-6)
        #expect(words[1].start == 0.4 && words[1].end == 0.72)
    }

    @Test func blanksAndPaddingAreSkipped() {
        let words = ParakeetEngine.words(from: [token("<blank>", 0, 0.1), token("▁um", 0.1, 0.3), token("<pad>", 0.3, 0.4)])
        #expect(words.map(\.text) == ["um"])
        #expect(words[0].end == 0.3)
    }

    @Test func aLeadingSpaceAlsoStartsAWord() {
        #expect(ParakeetEngine.words(from: [token(" a", 0, 0.1), token(" b", 0.1, 0.2)]).map(\.text) == ["a", "b"])
    }

    @Test func noTokensNoWords() {
        #expect(ParakeetEngine.words(from: []).isEmpty)
    }
}

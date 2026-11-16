import Testing
@testable import TranscribeKit

struct NemotronLiteEngineTests {
    @Test func aWordEndsWhereTheNextStartsAndTheLastWithTheAudio() {
        let words = NemotronLiteEngine.words([("so", 0.4), ("this", 0.72), ("works", 1.0)], duration: 2.5)
        #expect(words.map(\.text) == ["so", "this", "works"])
        #expect(words.map(\.start) == [0.4, 0.72, 1.0])
        #expect(words.map(\.end) == [0.72, 1.0, 2.5])
        #expect(NemotronLiteEngine.words([], duration: 1).isEmpty)
        // A start past the audio's reported end never gives a word that ends before it starts.
        #expect(NemotronLiteEngine.words([("late", 3)], duration: 2.5).first?.end == 3)
    }
}

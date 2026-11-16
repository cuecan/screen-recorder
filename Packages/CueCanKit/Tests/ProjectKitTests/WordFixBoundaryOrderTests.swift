import Testing
@testable import ProjectKit

struct WordFixBoundaryOrderTests {
    @Test func clampedCorrectionStaysBeforeTheFollowingWordAtTheSameTime() throws {
        let transcript = Transcript(source: SourceID(number: 1), engine: "fixture", silenceDetector: "fixture", language: "en", audioDuration: 3, items: [
            .word(Word(id: WordID(number: 1), text: "tabs", start: 0, end: 0.8)),
            .word(Word(id: WordID(number: 2), text: "over", start: 0.8, end: 1)),
            .word(Word(id: WordID(number: 3), text: "to", start: 1, end: 1.3)),
        ])
        let fix = WordFix(replaces: ItemRange(.word(WordID(number: 2))), words: [
            Word(id: WordID(number: 10), text: "over", start: 1.1, end: 1.4),
        ], isTimed: true)
        let fixed = try #require(transcript.applying(fix))
        #expect(fixed.words.map(\.text) == ["tabs", "over", "to"])
        #expect(fixed.words[1].start == 1 && fixed.words[1].end == 1)
    }

    @Test func severalClampedWordsRetainTheirTypedOrder() throws {
        let transcript = Transcript(source: SourceID(number: 1), engine: "fixture", silenceDetector: "fixture", language: "en", audioDuration: 3, items: [
            .word(Word(id: WordID(number: 1), text: "old", start: 0, end: 1)),
            .word(Word(id: WordID(number: 2), text: "next", start: 1, end: 2)),
        ])
        let fix = WordFix(replaces: ItemRange(.word(WordID(number: 1))), words: [
            Word(id: WordID(number: 10), text: "first", start: 1.1, end: 1.2),
            Word(id: WordID(number: 11), text: "second", start: 1.2, end: 1.3),
        ], isTimed: true)
        #expect(try #require(transcript.applying(fix)).words.map(\.text) == ["first", "second", "next"])
    }
}

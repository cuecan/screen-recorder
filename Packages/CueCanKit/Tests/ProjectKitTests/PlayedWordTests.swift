import Foundation
import Testing
@testable import ProjectKit

struct PlayedWordTests {
    @Test func repetitionsSpeedClippedEdgesAndSpellingsShareOneProjection() throws {
        let source = SourceID(number: 1)
        let transcripts = TranscriptIndex([talkingHead])
        let edit = Edit(main: [
            Clip(id: ClipID(number: 1), source: source, sourceIn: 1.1, sourceOut: 2.9),
            Clip(id: ClipID(number: 2), source: source, sourceIn: 1.1, sourceOut: 2.9,
                 speed: try #require(ClipSpeed(rate: 2)))
        ])
        let spellings = VocabularySpellings(source: source, terms: ["Hi there"], spellings: [.init(words: range(w(1), w(2)), text: "Hi there")])
        let words = PlayedWord.project(edit: edit, placements: edit.placements, transcripts: transcripts, spellings: [source: spellings])
        #expect(words.map(\.text) == ["Hi there", "", "Um,", "Hi there", "", "Um,"])
        #expect(words.map(\.isFiller) == [false, false, true, false, false, true])
        #expect(words[0].range.start == 0)
        #expect(words[0].range.duration.isClose(to: 0.3))
        #expect(words[3].range.start.isClose(to: 1.8))
        #expect(words[3].range.duration.isClose(to: 0.15))
        #expect(words[0].id == words[3].id)
        #expect(words[0].clip != words[3].clip)
        #expect(Set(words.map(\.occurrenceID)).count == words.count)
        let phrases = PlayedWord.phrases(words)
        #expect(phrases.count == 4)
        #expect(Set(phrases.map(\.id)).count == phrases.count)
        #expect(phrases[0].words == range(w(1), w(2)))
        #expect(phrases[0].text == "Hi there …")
        #expect(phrases[1].text == "Um,")
        let short = PlayedWord.phrases(words, maximumCharacters: 3)
        #expect(short.count == words.count)
        #expect(short.first?.text == "Hi there")
    }
}

import Testing
@testable import ProjectKit

struct FixAlignmentContextTests {
    @Test func anUntimedFixInTheContextCountsAllOfItsWords() throws {
        let transcript = TranscriptBuilder.make(source: SourceID(number: 1), duration: 4, [
            .word("Hello there", 1, 1.8), .word("world", 2, 2.5), .word("over here", 3, 3.5),
        ])
        let window = try #require(try FixAlignmentContext(transcript: transcript, replacing: range(w(2), w(2)), text: "everyone",
            audioRange: TimeRange(start: 0, end: 4), context: 3, padding: 0.3))
        #expect(window.text == "Hello there everyone over here")
        #expect(window.correctedWords == 2..<3)
    }

    @Test func aLateMicrophoneStartsTheAlignmentAtItsActualSourceTime() throws {
        let transcript = TranscriptBuilder.make(source: SourceID(number: 1), duration: 3, [
            .word("Hello", 0.6, 0.9), .word("world", 1, 1.3),
        ])
        let window = try #require(try FixAlignmentContext(transcript: transcript, replacing: range(w(1), w(1)), text: "Hi",
            audioRange: TimeRange(start: 0.5, end: 3), context: 3, padding: 0.3))
        #expect(window.sourceRange.start == 0.5, "File time zero is source time 0.5, never source time 0.3.")
        #expect(window.fileRange.start == 0)
        #expect(window.fileRange.end + 0.5 == window.sourceRange.end)
        #expect(window.text == "Hi world")
        #expect(window.correctedWords == 0..<1)
    }

    @Test func contextKeepsOnlyNearbyWordsAndCannotReadBeyondTheAudio() throws {
        let window = try #require(try FixAlignmentContext(transcript: talkingHead, replacing: range(w(4), w(5)), text: "These were",
            audioRange: TimeRange(start: 0, end: 4), context: 0.5, padding: 1))
        #expect(window.text == "Um, These were the")
        #expect(window.correctedWords == 1..<3)
        #expect(window.fileRange.end == 4)
        #expect(try FixAlignmentContext(transcript: talkingHead, replacing: range(w(4), w(5)), text: " ",
            audioRange: TimeRange(start: 0, end: 7), context: 3, padding: 0.3) == nil)
    }
}

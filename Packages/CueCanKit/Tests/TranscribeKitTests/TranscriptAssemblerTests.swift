import AudioKit
import Foundation
import ProjectKit
import Testing
@testable import TranscribeKit

@Suite struct TranscriptAssemblerTests {
    func kinds(_ draft: TranscriptDraft) -> [String] {
        draft.items.map { item in
            switch item {
            case .word(let word): word.text
            case .silence(let start, let end): "[\(start)–\(end)]"
            }
        }
    }

    @Test func silencesGoBetweenTheRightWords() {
        let draft = TranscriptAssembler.draft(
            words: [
                TimedWord(text: "Hello", start: 1.0, end: 1.4),
                TimedWord(text: "there.", start: 1.45, end: 1.8),
                TimedWord(text: "Next", start: 2.6, end: 3.0),
            ],
            silences: [TimeRange(start: 0, end: 1.0), TimeRange(start: 1.8, end: 2.6), TimeRange(start: 3.0, end: 4.0)],
            duration: 4,
            engine: "test",
            silenceDetector: "energy",
            language: "en"
        )
        #expect(kinds(draft) == ["[0.0–1.0]", "Hello", "there.", "[1.8–2.6]", "Next", "[3.0–4.0]"])
        #expect(draft.audioDuration == 4)
        #expect(draft.engine == "test")
        #expect(draft.silenceDetector == "energy")
    }

    @Test func aSilenceKeepsItsOwnEdgesWhenAWordRunsIntoIt() {
        let draft = TranscriptAssembler.draft(
            words: [TimedWord(text: "long", start: 0.5, end: 1.6), TimedWord(text: "next", start: 2.4, end: 3.0)],
            silences: [TimeRange(start: 1.4, end: 2.5)],
            duration: 3,
            engine: "test", silenceDetector: "energy", language: nil
        )
        #expect(kinds(draft) == ["long", "[1.4–2.5]", "next"])
    }

    @Test func aQuietWordInsideASilenceSplitsIt() {
        let draft = TranscriptAssembler.draft(
            words: [
                TimedWord(text: "before", start: 0, end: 1),
                TimedWord(text: "um", start: 2.0, end: 2.3),
                TimedWord(text: "after", start: 4, end: 5),
            ],
            silences: [TimeRange(start: 1, end: 4)],
            duration: 5,
            engine: "test", silenceDetector: "energy", language: nil
        )
        #expect(kinds(draft) == ["before", "[1.0–2.0]", "um", "[2.3–4.0]", "after"])
    }

    @Test func tinyLeftoverSilenceIsDropped() {
        let draft = TranscriptAssembler.draft(
            words: [TimedWord(text: "a", start: 1.02, end: 1.9)],
            silences: [TimeRange(start: 1, end: 2)],
            duration: 2,
            engine: "test", silenceDetector: "energy", language: nil
        )
        #expect(kinds(draft) == ["a", "[1.9–2.0]"])
    }

    @Test func wordsAreCleanedAndOrdered() {
        let draft = TranscriptAssembler.draft(
            words: [
                TimedWord(text: " second", start: 2, end: 2.5),
                TimedWord(text: "  ", start: 1.5, end: 1.6),
                TimedWord(text: "first ", start: -0.2, end: 0.5),
                TimedWord(text: "backwards", start: 3, end: 2.8),
                TimedWord(text: "past", start: 9, end: 12),
            ],
            silences: [],
            duration: 10,
            engine: "test", silenceDetector: "energy", language: nil
        )
        guard case .word(let first) = draft.items[0], case .word(let backwards) = draft.items[2],
            case .word(let past) = draft.items[3]
        else {
            Issue.record("Expected four words, got \(draft.items)")
            return
        }
        #expect(kinds(draft) == ["first", "second", "backwards", "past"])
        #expect(first.start == 0)
        #expect(backwards.end == backwards.start)
        #expect(past.end == 10)
    }

    @Test func fillersAreMarked() {
        let draft = TranscriptAssembler.draft(
            words: [TimedWord(text: "Um,", start: 0, end: 0.3), TimedWord(text: "like", start: 0.4, end: 0.6)],
            silences: [],
            duration: 1,
            engine: "test", silenceDetector: "energy", language: nil
        )
        let fillers = draft.items.compactMap { item -> Bool? in
            if case .word(let word) = item { word.isFiller } else { nil }
        }
        #expect(fillers == [true, false])
    }

    @Test(arguments: ["um", "Um,", "UH", "hmm…", "Erm."])
    func fillerWords(text: String) {
        #expect(FillerWords.isFiller(text))
    }

    @Test(arguments: ["like", "so", "umbrella", "her", "a", ""])
    func notFillerWords(text: String) {
        #expect(!FillerWords.isFiller(text))
    }

    @Test func draftsBecomeTranscriptsTheSnapperCanCut() throws {
        let draft = TranscriptAssembler.draft(
            words: [TimedWord(text: "one", start: 0.5, end: 1), TimedWord(text: "two", start: 2, end: 2.5)],
            silences: [TimeRange(start: 0, end: 0.5), TimeRange(start: 1, end: 2), TimeRange(start: 2.5, end: 3)],
            duration: 3,
            engine: "test", silenceDetector: "energy", language: "en"
        )
        let transcript = draft.assigningIDs(source: SourceID(number: 1), firstWordNumber: 1, firstSilenceNumber: 1).transcript
        let time = try CutPointSnapper(transcript: transcript, settings: SnapSettings(leadPad: 0.05, trailPad: 0.1))
            .timeRange(for: ItemRange(.word(WordID(number: 2))))
        #expect(abs(time.start - 1.95) < 1e-9)
        #expect(abs(time.end - 2.6) < 1e-9)
    }
}

@Suite struct OverlappingTimingRegressionTests {
    @Test func silencePlacementDoesNotAssumeWordMiddlesAreSorted() {
        let draft = TranscriptAssembler.draft(
            words: [TimedWord(text: "one", start: 0, end: 4), TimedWord(text: "two", start: 1, end: 1.2)],
            silences: [TimeRange(start: 1.4, end: 1.6)], duration: 5,
            engine: "test", silenceDetector: "test", language: "en"
        )
        guard case .silence = draft.items.first else {
            Issue.record("The silence must precede the first word whose middle follows it.")
            return
        }
    }

    @Test func laterSilencesStillLandBetweenTheRightWords() {
        // Middles 2, 1.1 and 5.5: out of order. The second silence's middle, 4.5, is first reached by "three".
        let draft = TranscriptAssembler.draft(
            words: [
                TimedWord(text: "one", start: 0, end: 4),
                TimedWord(text: "two", start: 1, end: 1.2),
                TimedWord(text: "three", start: 5, end: 6),
            ],
            silences: [TimeRange(start: 1.4, end: 1.6), TimeRange(start: 4.2, end: 4.8)], duration: 7,
            engine: "test", silenceDetector: "test", language: "en"
        )
        let kinds = draft.items.map { item -> String in
            if case .word(let word) = item { word.text } else { "silence" }
        }
        #expect(kinds == ["silence", "one", "two", "silence", "three"])
    }
}

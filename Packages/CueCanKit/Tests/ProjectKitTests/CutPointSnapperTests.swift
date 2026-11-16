import Foundation
import Testing
@testable import ProjectKit

/// Boundaries in `talkingHead` with `testPads` (lead 0.05, trail 0.1).
@Suite struct CutPointSnapperTests {
    let snapper = CutPointSnapper(transcript: talkingHead, settings: testPads)

    @Test(arguments: [
        (0, 0.0),  // before the opening silence: its start
        (1, 0.95),  // silence → "Hello": lead pad before the word
        (2, 1.425),  // "Hello" → "there." with no silence: halfway
        (3, 1.9),  // "there." → silence: trail pad into the silence
        (4, 2.55),  // silence → "Um,"
        (5, shortPauseEdge),  // "Um," → a 0.1 s silence, shorter than both pads: split in their ratio
        (6, shortPauseEdge),  // that short silence → "this": the same edge
        (10, 4.2),  // "take." → long pause
        (11, 5.55),  // long pause → "This"
        (15, 6.8),  // "take." → closing silence
        (16, 7.0),  // after the closing silence: its end
    ])
    func boundaries(index: Int, expected: Double) {
        #expect(snapper.boundary(before: index).isClose(to: expected))
    }

    @Test func wordsAtTheEdgesOfTheAudioArePaddedWithinIt() {
        let transcript = TranscriptBuilder.make(
            source: SourceID(number: 1),
            duration: 1.0,
            [.word("Hi", 0.02, 0.5), .word("there", 0.55, 0.95)]
        )
        let snapper = CutPointSnapper(transcript: transcript, settings: testPads)
        #expect(snapper.boundary(before: 0) == 0, "Never before the start of the audio.")
        #expect(snapper.boundary(before: 2) == 1.0, "Never past the end of the audio.")
    }

    @Test func silenceWinsOverAnAlignedTimeThatRunsIntoIt() throws {
        // The aligner says "late" runs until 2.0, but the audio is quiet from 1.5.
        let transcript = TranscriptBuilder.make(
            source: SourceID(number: 1),
            duration: 3.0,
            [.word("late", 1.0, 2.0), .silence(1.5, 2.5), .word("next", 2.5, 3.0)]
        )
        let snapper = CutPointSnapper(transcript: transcript, settings: testPads)
        #expect(snapper.boundary(before: 1).isClose(to: 1.6))
        #expect(snapper.boundary(before: 2).isClose(to: 2.45))
    }

    @Test func aPauseTooShortForBothPadsIsSplitInTheirRatio() throws {
        // 40 ms of pause, against 20 ms of lead and 60 ms of trail: three quarters go to the word before.
        let transcript = TranscriptBuilder.make(
            source: SourceID(number: 1),
            duration: 2.0,
            [.word("fade", 0.5, 1.0), .silence(1.0, 1.04), .word("next", 1.04, 1.5)]
        )
        let snapper = CutPointSnapper(transcript: transcript, settings: SnapSettings(leadPad: 0.02, trailPad: 0.06))
        #expect(snapper.boundary(before: 1).isClose(to: 1.03))
        #expect(snapper.boundary(before: 2) == snapper.boundary(before: 1), "Both sides of the pause share one edge.")
    }

    @Test func rangeOfWordsPlaysFromBoundaryToBoundary() throws {
        let time = try snapper.timeRange(for: range(w(1), w(2)))
        #expect(time.start.isClose(to: 0.95))
        #expect(time.end.isClose(to: 1.9))
    }

    @Test func rangeCanStartAndEndOnSilences() throws {
        let time = try snapper.timeRange(for: range(s(2), s(4)))
        #expect(time.start.isClose(to: 1.9))
        #expect(time.end.isClose(to: 5.55))
    }

    @Test func silenceShorterThanThePadsIsEmpty() throws {
        let time = try snapper.timeRange(for: ItemRange(s(3)))
        #expect(time.isEmpty)
        #expect(time.start.isClose(to: shortPauseEdge))
    }

    @Test func singleWordRange() throws {
        let time = try snapper.timeRange(for: ItemRange(w(3)))
        #expect(time.start.isClose(to: 2.55))
        #expect(time.end.isClose(to: shortPauseEdge))
    }

    @Test func unknownIDsAreReported() {
        #expect(throws: EditError.unknownItem(w(99))) { try snapper.timeRange(for: range(w(1), w(99))) }
        #expect(throws: EditError.unknownItem(s(99))) { try snapper.timeRange(for: range(s(99), w(1))) }
    }

    @Test func rangeOutOfOrderIsReported() {
        #expect(throws: EditError.rangeOutOfOrder(range(w(5), w(2)))) {
            try snapper.timeRange(for: range(w(5), w(2)))
        }
    }

    @Test func boundariesNeverGoBackwardsWithinAnItem() throws {
        // For every single item, its end boundary is at or after its start boundary, unless padding makes
        // it empty (only the 0.1 s silence here).
        for index in talkingHead.items.indices {
            let start = snapper.boundary(before: index)
            let end = snapper.boundary(before: index + 1)
            #expect(end >= start, "Adjacent ranges must not overlap, even around a short silence.")
            if talkingHead.items[index].id != s(3) {
                #expect(end > start, "Item \(talkingHead.items[index].id) has no time to play.")
            }
        }
    }
}

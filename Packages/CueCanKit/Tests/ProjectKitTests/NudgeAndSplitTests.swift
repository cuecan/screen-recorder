import Foundation
import Testing
@testable import ProjectKit

@Suite struct NudgeAndSplitTests {
    let transcripts = TranscriptIndex([talkingHead, secondAngle])

    /// All of `talkingHead` as one clip, 0–7 s.
    func wholeTake() throws -> Edit {
        var edit = Edit()
        try edit.addClip(range(s(1), s(5)), transcripts: transcripts, snapping: testPads)
        return edit
    }

    /// The whole take with the first "this is the take." cut: c_1 plays 0–2.967 (`shortPauseEdge`), c_2 plays 4.2–7.
    func cutTake() throws -> Edit {
        var edit = try wholeTake()
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        return edit
    }

    // MARK: - Nudging

    @Test func nudgingMovesOneEdgeAndKeepsTheSnappedOne() throws {
        var edit = try wholeTake()
        let result = try edit.nudge(.start, of: ClipID(number: 1), by: 0.04, transcripts: transcripts)
        let clip = edit.main[0]
        #expect(clip.sourceIn == 0, "The snapped edge stays as it was.")
        #expect(clip.startNudge.isClose(to: 0.04))
        #expect(clip.playedRange.start.isClose(to: 0.04))
        #expect(edit.duration.isClose(to: 6.96))
        #expect(result.edgeTime.isClose(to: 0.04))
        #expect(result.wordsAtEdge.isEmpty, "0.04 s is in the opening silence.")
    }

    @Test func aNudgeIntoAWordIsFlagged() throws {
        var edit = try cutTake()
        // c_1 ends at about 2.967, in the short pause after "Um," (2.6–2.9).
        #expect(try edit.nudge(.end, of: ClipID(number: 1), by: -0.03, transcripts: transcripts).wordsAtEdge.isEmpty)
        let into = try edit.nudge(.end, of: ClipID(number: 1), by: -0.07, transcripts: transcripts)
        #expect(into.edgeTime.isClose(to: shortPauseEdge - 0.1), "The two nudges add up.")
        #expect(into.wordsAtEdge == [WordID(number: 3)])
    }

    @Test func nudgesHaveNoLimit() throws {
        var edit = try wholeTake()
        try edit.nudge(.end, of: ClipID(number: 1), by: -0.3, transcripts: transcripts)
        try edit.nudge(.end, of: ClipID(number: 1), by: -0.9, transcripts: transcripts)
        #expect(edit.main[0].endNudge.isClose(to: -1.2), "Nudges add up, with no half-second limit (docs/decisions.md, 56).")
        try edit.nudge(.end, of: ClipID(number: 1), by: 1.2, transcripts: transcripts)
        #expect(edit.main[0].endNudge.isClose(to: 0))
    }

    @Test func aNudgeCantGoPastTheRecording() throws {
        var edit = try wholeTake()
        #expect(throws: EditError.nudgeOutsideRecording(ClipID(number: 1))) {
            try edit.nudge(.start, of: ClipID(number: 1), by: -0.1, transcripts: transcripts)
        }
        #expect(throws: EditError.nudgeOutsideRecording(ClipID(number: 1))) {
            try edit.nudge(.end, of: ClipID(number: 1), by: 0.1, transcripts: transcripts)
        }
    }

    @Test func aNudgeMustLeaveSomethingToPlay() throws {
        var edit = Edit()
        // "Hello" alone: 0.95 to 1.425.
        try edit.addClip(ItemRange(w(1)), transcripts: transcripts, snapping: testPads)
        #expect(throws: EditError.nudgeLeavesTooLittle(ClipID(number: 1))) {
            try edit.nudge(.start, of: ClipID(number: 1), by: 0.46, transcripts: transcripts)
        }
    }

    @Test func nudgingAnUnknownClipFails() throws {
        var edit = try wholeTake()
        #expect(throws: EditError.unknownClip(ClipID(number: 9))) {
            try edit.nudge(.start, of: ClipID(number: 9), by: 0.01, transcripts: transcripts)
        }
    }

    @Test func aCutKeepsNudgesOnTheEdgesItDoesntMove() throws {
        var edit = try wholeTake()
        try edit.nudge(.start, of: ClipID(number: 1), by: 0.04, transcripts: transcripts)
        try edit.nudge(.end, of: ClipID(number: 1), by: -0.05, transcripts: transcripts)
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.count == 2)
        #expect(edit.main[0].startNudge.isClose(to: 0.04))
        #expect(edit.main[0].endNudge == 0, "The cut made this edge, so it starts fresh.")
        #expect(edit.main[1].startNudge == 0)
        #expect(edit.main[1].endNudge.isClose(to: -0.05))
    }

    @Test func keepingPastANudgedEdgeResetsIt() throws {
        var edit = try cutTake()
        try edit.nudge(.end, of: ClipID(number: 1), by: -0.02, transcripts: transcripts)
        try edit.keep(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.count == 1)
        #expect(edit.main[0].endNudge == 0)
        #expect(edit.main[0].playedRange == TimeRange(start: 0, end: 7))
    }

    @Test func cuttingAWordANudgeBroughtInRemovesIt() throws {
        var edit = Edit()
        try edit.addClip(range(w(4), w(6)), transcripts: transcripts, snapping: testPads)  // 2.967–3.7, "this is the"
        try edit.nudge(.end, of: ClipID(number: 1), by: 0.4, transcripts: transcripts)      // now plays "take." too
        let removed = try edit.cut(ItemRange(w(7)), transcripts: transcripts, snapping: testPads)
        #expect(removed.isClose(to: 0.4))
        #expect(edit.main.count == 1)
        #expect(edit.main[0].playedRange.end.isClose(to: 3.7))
        #expect(edit.main[0].endNudge == 0, "The cut made this edge.")
    }

    @Test(arguments: [false, true])
    func restoringPastANudgedEndDoesntRepeatAnotherClip(partialGap: Bool) {
        let source = SourceID(number: 1)
        let nudged = Clip(id: ClipID(number: 1), source: source, sourceIn: 0, sourceOut: 1, endNudge: -0.2)
        let other = Clip(id: ClipID(number: 2), source: source, sourceIn: 0.8, sourceOut: partialGap ? 0.9 : 1)
        var edit = Edit(main: [nudged, other])
        edit.nextClipNumber = 3
        let before = edit.duration

        edit.restore(TimeRange(start: 1, end: 2), from: source)

        #expect((edit.duration - before).isClose(to: 1))
        #expect(edit.main.first == nudged, "Restoring must not bridge into another clip's audio.")
        #expect(edit.main.last?.playedRange.end == 2)
        for (previous, next) in zip(edit.main, edit.main.dropFirst()) {
            #expect(!previous.playedRange.overlaps(next.playedRange))
        }
    }

    @Test(arguments: [false, true])
    func restoringBeforeANudgedStartDoesntRepeatAnotherClip(partialGap: Bool) {
        let source = SourceID(number: 1)
        let nudged = Clip(id: ClipID(number: 1), source: source, sourceIn: 1, sourceOut: 2, startNudge: 0.2)
        let other = Clip(id: ClipID(number: 2), source: source, sourceIn: partialGap ? 1.1 : 1, sourceOut: 1.2)
        // Put the nudged clip first so the search encounters its snapped edge before the other clip.
        var edit = Edit(main: [nudged, other])
        edit.nextClipNumber = 3
        let before = edit.duration

        edit.restore(TimeRange(start: 0, end: 1), from: source)

        #expect((edit.duration - before).isClose(to: 1))
        #expect(edit.main.first(where: { $0.id == nudged.id }) == nudged)
        let others = edit.main.filter { $0.id != nudged.id }
        #expect(others.contains { $0.playedRange.start == 0 })
        for clip in others {
            #expect(!clip.playedRange.overlaps(nudged.playedRange))
        }
    }

    @Test func keepingWhatANudgeAlreadyPlaysDoesntPlayItTwice() throws {
        var edit = Edit()
        try edit.addClip(range(w(4), w(5)), transcripts: transcripts, snapping: testPads)  // 2.967–3.5, "this is"
        try edit.nudge(.end, of: ClipID(number: 1), by: 0.45, transcripts: transcripts)     // plays to 3.95
        let added = try edit.keep(ItemRange(w(7)), transcripts: transcripts, snapping: testPads)  // "take.", 3.7–4.2
        #expect(edit.main.count == 1, "The nudged clip grows; no second clip repeats 3.7–3.95.")
        #expect(edit.main[0].playedRange.start.isClose(to: shortPauseEdge))
        #expect(edit.main[0].playedRange.end.isClose(to: 4.2))
        #expect(added.isClose(to: 0.25))
    }

    @Test func aCutInsideANudgedEdgeLeavesValidClips() throws {
        var edit = Edit()
        try edit.addClip(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)  // 2.967–4.2
        try edit.nudge(.start, of: ClipID(number: 1), by: 2.6 - shortPauseEdge, transcripts: transcripts)  // plays from 2.6, "Um," and all
        try edit.cut(range(w(4), w(6)), transcripts: transcripts, snapping: testPads)       // 2.967–3.7
        try #require(edit.main.count == 2)
        for clip in edit.main {
            #expect(clip.sourceIn < clip.sourceOut, "Snapped range \(clip.sourceRange) is backwards.")
        }
        #expect(edit.main[0].playedRange.start.isClose(to: 2.6))
        #expect(edit.main[0].playedRange.end.isClose(to: shortPauseEdge))
        #expect(edit.main[1].playedRange.start.isClose(to: 3.7))
    }

    @Test func theWordsUsedFollowTheNudge() throws {
        var edit = Edit()
        try edit.addClip(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)  // 0.95–1.9
        try edit.nudge(.end, of: ClipID(number: 1), by: -0.45, transcripts: transcripts)   // now ends at 1.45
        let used = edit.usedItems(of: talkingHead)
        #expect(used.contains(w(1)))
        #expect(!used.contains(w(2)), "“there.” now ends after the clip does.")
    }

    @Test func nudgesAreWrittenOnlyWhenSet() throws {
        var edit = try wholeTake()
        let plain = String(decoding: try ProjectJSON.encoder.encode(edit.main[0]), as: UTF8.self)
        #expect(!plain.contains("Nudge"))
        #expect(!plain.contains("startsAtSplit"))
        try edit.nudge(.start, of: ClipID(number: 1), by: 0.03, transcripts: transcripts)
        let data = try ProjectJSON.encoder.encode(edit)
        #expect(String(decoding: data, as: UTF8.self).contains("startNudge"))
        #expect(try ProjectJSON.decoder.decode(Edit.self, from: data) == edit)
    }

    // MARK: - Splitting

    @Test func splittingDividesAClipWithoutRemovingAnything() throws {
        var edit = try wholeTake()
        let (first, second) = try edit.split(ClipID(number: 1), before: WordID(number: 8), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.map(\.id) == [ClipID(number: 1), ClipID(number: 2)])
        #expect(first.playedRange.start == 0)
        #expect(first.playedRange.end.isClose(to: 5.55), "Where a cut before “This” would land.")
        #expect(second.playedRange.start.isClose(to: 5.55))
        #expect(second.playedRange.end.isClose(to: 7))
        #expect(second.startsAtSplit)
        #expect(edit.duration.isClose(to: 7))
    }

    @Test func splitPartsCanHaveTheirOwnLayoutsAndAreNeverRejoined() throws {
        var edit = try wholeTake()
        try edit.split(ClipID(number: 1), before: WordID(number: 8), transcripts: transcripts, snapping: testPads)
        try edit.setLayout(.camera, for: ClipID(number: 2))
        #expect(edit.main.map(\.layout) == [.automatic, .camera])

        // Even with the same layout, a cut and keep elsewhere doesn't join the parts back up.
        try edit.setLayout(.automatic, for: ClipID(number: 2))
        try edit.cut(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        try edit.keep(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.count == 2)
        #expect(edit.main[1].startsAtSplit)
    }

    @Test func nudgingSplitPartsIntoEachOtherMovesTheSplit() throws {
        var edit = try wholeTake()
        try edit.split(ClipID(number: 1), before: WordID(number: 8), transcripts: transcripts, snapping: testPads)
        let split = edit.main[1].playedRange.start
        let duration = edit.duration
        try edit.nudge(.start, of: ClipID(number: 2), by: -0.1, transcripts: transcripts)
        #expect(edit.main[0].playedRange.end.isClose(to: split - 0.1))
        #expect(edit.main[1].playedRange.start.isClose(to: split - 0.1))
        try edit.nudge(.end, of: ClipID(number: 1), by: 0.2, transcripts: transcripts)
        #expect(edit.main[1].playedRange.start.isClose(to: split + 0.1))
        #expect(edit.duration.isClose(to: duration), "A roll moves the split, never replays or drops time.")
        // Pulling them apart leaves a cut between them.
        try edit.nudge(.start, of: ClipID(number: 2), by: 0.05, transcripts: transcripts)
        #expect(edit.main[0].playedRange.end.isClose(to: split + 0.1))
        #expect(!edit.main[1].startsAtSplit)
        #expect(!edit.joinRolls(after: 0))
        // Back by more than the cut: it stops where the first part ends, and they roll again.
        try edit.nudge(.start, of: ClipID(number: 2), by: -0.2, transcripts: transcripts)
        #expect(edit.main[0].playedRange.end.isClose(to: split + 0.1))
        #expect(edit.main[1].playedRange.start.isClose(to: split + 0.1))
        #expect(edit.joinRolls(after: 0))
    }

    @Test func aSplitInsideANudgedEdgeLeavesValidClips() throws {
        var edit = Edit()
        try edit.addClip(range(w(4), w(5)), transcripts: transcripts, snapping: testPads)  // 2.967–3.5
        try edit.nudge(.end, of: ClipID(number: 1), by: 0.45, transcripts: transcripts)     // plays to 3.95
        let (first, second) = try edit.split(ClipID(number: 1), before: WordID(number: 7), transcripts: transcripts, snapping: testPads)
        #expect(first.playedRange == TimeRange(start: shortPauseEdge, end: 3.7))
        #expect(second.playedRange.start.isClose(to: 3.7))
        #expect(second.playedRange.end.isClose(to: 3.95))
        #expect(second.sourceIn < second.sourceOut)
        #expect(edit.duration.isClose(to: 3.95 - shortPauseEdge), "A split removes nothing.")
    }

    @Test func aSplitHasToFallInsideTheClip() throws {
        var edit = Edit()
        try edit.addClip(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)  // 0.95–1.9
        #expect(throws: EditError.splitOutsideClip(WordID(number: 1), ClipID(number: 1))) {
            try edit.split(ClipID(number: 1), before: WordID(number: 1), transcripts: transcripts, snapping: testPads)
        }
        #expect(throws: EditError.splitOutsideClip(WordID(number: 8), ClipID(number: 1))) {
            try edit.split(ClipID(number: 1), before: WordID(number: 8), transcripts: transcripts, snapping: testPads)
        }
        #expect(throws: EditError.splitOutsideClip(WordID(number: 13), ClipID(number: 1))) {
            try edit.split(ClipID(number: 1), before: WordID(number: 13), transcripts: transcripts, snapping: testPads)
        }
        // Before the clip's second word is fine.
        try edit.split(ClipID(number: 1), before: WordID(number: 2), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.count == 2)
    }
}

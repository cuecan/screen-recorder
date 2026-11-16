import Foundation
import Testing
@testable import ProjectKit

@Suite struct EditCuttingTests {
    let transcripts = TranscriptIndex([talkingHead, secondAngle])
    let source1 = SourceID(number: 1)
    let source2 = SourceID(number: 2)

    /// An edit that plays all of `talkingHead` as one clip, 0–7 s.
    func wholeTake() throws -> Edit {
        var edit = Edit()
        try edit.addClip(range(s(1), s(5)), transcripts: transcripts, snapping: testPads)
        return edit
    }

    func times(_ edit: Edit) -> [[Double]] {
        edit.main.map { [$0.sourceIn, $0.sourceOut] }
    }

    func expectTimes(_ edit: Edit, _ expected: [[Double]], sourceLocation: SourceLocation = #_sourceLocation) {
        let actual = times(edit)
        let matches = actual.count == expected.count
            && zip(actual, expected).allSatisfy { $0[0].isClose(to: $1[0]) && $0[1].isClose(to: $1[1]) }
        #expect(matches, "Expected clips \(expected), got \(actual)", sourceLocation: sourceLocation)
    }

    // MARK: - Adding

    @Test func addingTheWholeTranscriptCoversTheAudio() throws {
        let edit = try wholeTake()
        expectTimes(edit, [[0, 7]])
        #expect(edit.main[0].id == ClipID(number: 1))
        #expect(edit.main[0].source == source1)
        #expect(edit.duration.isClose(to: 7))
    }

    @Test func clipsCanBeAddedAtAPosition() throws {
        var edit = Edit()
        try edit.addClip(range(w(8), w(11)), transcripts: transcripts, snapping: testPads)
        try edit.addClip(range(w(1), w(2)), at: 0, layout: .camera, transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0.95, 1.9], [5.55, 6.8]])
        #expect(edit.main[0].layout == .camera)
        #expect(edit.main.map(\.id) == [ClipID(number: 2), ClipID(number: 1)])
    }

    @Test func positionOffTheTimelineIsRejected() {
        var edit = Edit()
        #expect(throws: EditError.invalidPosition(2, clipCount: 0)) {
            try edit.addClip(range(w(1), w(2)), at: 2, transcripts: transcripts)
        }
        #expect(edit.main.isEmpty)
        #expect(edit.nextClipNumber == 1, "A failed add doesn't use up an id.")
    }

    @Test func rangeAcrossTwoSourcesIsRejected() {
        var edit = Edit()
        #expect(throws: EditError.rangeSpansSources(range(w(1), w(12)))) {
            try edit.addClip(range(w(1), w(12)), transcripts: transcripts)
        }
    }

    // MARK: - Cutting

    @Test func cuttingTheMiddleSplitsTheClip() throws {
        var edit = try wholeTake()
        // Cut the first take of "this is the take."
        let removed = try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0, shortPauseEdge], [4.2, 7]])
        #expect(removed.isClose(to: 4.2 - shortPauseEdge))
        #expect(edit.main.map(\.id) == [ClipID(number: 1), ClipID(number: 2)], "The second piece is a new clip.")
    }

    @Test func cuttingAtTheStartTrimsTheClip() throws {
        var edit = try wholeTake()
        try edit.cut(range(s(1), w(3)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[shortPauseEdge, 7]])
        #expect(edit.main[0].id == ClipID(number: 1))
    }

    @Test func cuttingEverythingEmptiesTheTimeline() throws {
        var edit = try wholeTake()
        try edit.cut(range(s(1), s(5)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.isEmpty)
    }

    @Test func cuttingASilenceShorterThanThePadsChangesNothing() throws {
        var edit = try wholeTake()
        let removed = try edit.cut(ItemRange(s(3)), transcripts: transcripts, snapping: testPads)
        #expect(removed == 0)
        expectTimes(edit, [[0, 7]])
    }

    @Test func cuttingWhatIsNotOnTheTimelineChangesNothing() throws {
        var edit = Edit()
        try edit.addClip(range(w(8), w(11)), transcripts: transcripts, snapping: testPads)
        let before = edit
        #expect(try edit.cut(range(w(1), w(2)), transcripts: transcripts) == 0)
        #expect(edit == before)
    }

    @Test func cuttingOneSourceLeavesTheOtherAlone() throws {
        var edit = try wholeTake()
        try edit.addClip(range(s(6), s(7)), transcripts: transcripts, snapping: testPads)
        try edit.cut(range(w(12), w(13)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0, 7], [0, 0.45], [1.7, 3.0]])
        #expect(edit.main.map(\.source) == [source1, source2, source2])
    }

    @Test func cutRemovesTheRangeFromEveryClipThatPlaysIt() throws {
        // The same take used twice, say as a cold open and in place.
        var edit = try wholeTake()
        try edit.addClip(range(w(4), w(7)), at: 0, transcripts: transcripts, snapping: testPads)
        try edit.cut(range(w(6), w(7)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[shortPauseEdge, 3.5], [0, 3.5], [4.2, 7]])
    }

    // MARK: - Keeping

    @Test func keepingWhatWasCutPutsItBack() throws {
        var edit = try wholeTake()
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        let added = try edit.keep(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0, 7]])
        #expect(added.isClose(to: 4.2 - shortPauseEdge))
        #expect(edit.main[0].id == ClipID(number: 1), "The pieces join back into the original clip.")
    }

    /// For every range in the transcript, cutting it from the whole take and keeping it again gives back
    /// the whole take.
    @Test func cutThenKeepIsAnIdentityForEveryRange() throws {
        let ids = talkingHead.items.map(\.id)
        for first in ids.indices {
            for last in first..<ids.count {
                var edit = try wholeTake()
                let itemRange = range(ids[first], ids[last])
                try edit.cut(itemRange, transcripts: transcripts, snapping: testPads)
                try edit.keep(itemRange, transcripts: transcripts, snapping: testPads)
                #expect(edit.main.count == 1, "\(itemRange) didn't join back into one clip.")
                #expect(edit.main.first?.sourceIn.isClose(to: 0) == true, "\(itemRange)")
                #expect(edit.main.first?.sourceOut.isClose(to: 7) == true, "\(itemRange)")
            }
        }
    }

    @Test func keepsInAnyOrderPutEverythingBack() throws {
        var edit = try wholeTake()
        try edit.cut(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        try edit.cut(range(w(9), w(10)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.count == 4)
        try edit.keep(range(w(9), w(10)), transcripts: transcripts, snapping: testPads)
        try edit.keep(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        try edit.keep(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0, 7]])
    }

    @Test func keepingWhatIsAlreadyThereAddsNothing() throws {
        var edit = try wholeTake()
        #expect(try edit.keep(range(w(1), w(5)), transcripts: transcripts, snapping: testPads) == 0)
        expectTimes(edit, [[0, 7]])
    }

    @Test func keepingSomethingNewPlacesItInSourceOrder() throws {
        var edit = Edit()
        try edit.addClip(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        try edit.addClip(range(s(6), s(7)), transcripts: transcripts, snapping: testPads)
        try edit.addClip(range(w(8), w(11)), transcripts: transcripts, snapping: testPads)

        // w_4…w_7 comes after w_1…w_2 in the source, so it goes straight after that clip.
        try edit.keep(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.map(\.source) == [source1, source1, source2, source1])
        expectTimes(edit, [[0.95, 1.9], [shortPauseEdge, 4.2], [0, 3.0], [5.55, 6.8]])
    }

    @Test func keepingBeforeEveryClipOfASourceGoesBeforeTheFirst() throws {
        var edit = Edit()
        try edit.addClip(range(s(6), s(7)), transcripts: transcripts, snapping: testPads)
        try edit.addClip(range(w(8), w(11)), transcripts: transcripts, snapping: testPads)
        try edit.keep(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.map(\.source) == [source2, source1, source1])
    }

    @Test func keepingASourceNotOnTheTimelineAppends() throws {
        var edit = Edit()
        try edit.addClip(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        try edit.keep(range(w(12), w(13)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main.map(\.source) == [source1, source2])
    }

    @Test func keepingNextToAClipExtendsIt() throws {
        var edit = Edit()
        try edit.addClip(range(w(1), w(2)), layout: .screen, transcripts: transcripts, snapping: testPads)
        try edit.keep(range(s(2), w(3)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0.95, shortPauseEdge]])
        #expect(edit.main[0].layout == .screen)
    }

    @Test func clipsWithDifferentLayoutsAreNotJoined() throws {
        var edit = try wholeTake()
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        try edit.setLayout(.camera, for: edit.main[1].id)
        try edit.keep(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        expectTimes(edit, [[0, 4.2], [4.2, 7]])
        #expect(edit.main.map(\.layout) == [.automatic, .camera])
    }

    // MARK: - Silences and fillers

    @Test func removingSilencesLeavesTheRequestedAir() throws {
        var edit = try wholeTake()
        let shortened = try edit.removeSilences(
            longerThan: 0.5, leaving: 0.3, transcripts: transcripts, snapping: testPads
        )
        // The air splits 2:1 like the pads (trail 0.1, lead 0.05): 0.2 s after a word, 0.1 s before the next.
        #expect(shortened == 3)
        expectTimes(edit, [[0, 0.2], [0.9, 2.0], [2.5, 4.3], [5.5, 7]])
        #expect(edit.duration.isClose(to: 4.6))
    }

    @Test func removingSilencesIgnoresPausesOffTheTimeline() throws {
        var edit = Edit()
        try edit.addClip(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        #expect(try edit.removeSilences(longerThan: 0.5, leaving: 0.3, transcripts: transcripts) == 0)
    }

    @Test(arguments: [(0.3, 0.3), (0.5, 0), (0.2, 0.3), (0.5, -0.1)])
    func silenceSettingsMustLeaveLessThanTheyRemove(threshold: Double, air: Double) throws {
        var edit = try wholeTake()
        #expect(throws: EditError.invalidSilenceSettings) {
            try edit.removeSilences(longerThan: threshold, leaving: air, transcripts: transcripts)
        }
    }

    @Test func theEditorsThresholdIsATenthOfASecondAndMoreThanTheAirLeft() {
        #expect(Edit.silenceThreshold(1.26) == 1.3)
        #expect(Edit.silenceThreshold(0.1) == 0.4 && Edit.silenceThreshold(60) == 9.9)
        #expect(Edit.silenceThreshold(.nan) == Edit.defaultSilenceThreshold)
        #expect(Edit.silenceThresholds.contains(Edit.defaultSilenceThreshold))
        #expect(Edit.silenceThresholds.lowerBound > Edit.defaultSilenceAir)
    }

    // The editor's commands act on the selected clips (docs/ui.md, "Remove Silences and Remove Fillers").

    @Test func removingSilencesInChosenClipsLeavesTheOthersAlone() throws {
        var edit = try wholeTake()
        let (first, second) = try edit.split(at: 3)
        // Only the second clip: of the three long pauses, only s_4 (4.1–5.6) is in it.
        #expect(try edit.removeSilences(longerThan: 0.5, leaving: 0.3, transcripts: transcripts, snapping: testPads, in: [second.id]) == 1)
        expectTimes(edit, [[0, 3], [3, 4.3], [5.5, 7]])
        #expect(edit.main[0] == first, "The clip not chosen is untouched.")
    }

    @Test func aChosenClipCutInTwoKeepsBothPiecesChosen() throws {
        var edit = try wholeTake()
        let (first, _) = try edit.split(at: 3)
        // s_1 cuts the first clip in two; s_2 then falls in the second piece, which is still chosen.
        #expect(try edit.removeSilences(longerThan: 0.5, leaving: 0.3, transcripts: transcripts, snapping: testPads, in: [first.id]) == 2)
        expectTimes(edit, [[0, 0.2], [0.9, 2.0], [2.5, 3], [3, 7]])
    }

    @Test func aChosenClipOnlyCutsWhatItPlaysNotTheSameTimeElsewhere() throws {
        // The same stretch played twice: the chosen copy loses its pause, the other keeps it.
        var edit = Edit()
        try edit.addClip(range(w(7), w(8)), transcripts: transcripts, snapping: testPads)
        try edit.addClip(range(w(7), w(8)), transcripts: transcripts, snapping: testPads)
        let chosen = edit.main[1].id
        #expect(try edit.removeSilences(longerThan: 0.5, leaving: 0.3, transcripts: transcripts, snapping: testPads, in: [chosen]) == 1)
        #expect(edit.main.count == 3)
        #expect(edit.main[0].playedRange.start <= 4.8 && 4.8 < edit.main[0].playedRange.end, "The first copy still plays the pause.")
    }

    // MARK: - Reading the cut

    @Test func usedItemsAreThoseTheTimelinePlays() throws {
        var edit = try wholeTake()
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        let used = edit.usedItems(of: talkingHead)
        // The short pause s_3 still plays its first two thirds, up to the shared edge, so it counts as used.
        let cut: Set<TranscriptItemID> = [w(4), w(5), w(6), w(7)]
        #expect(used == Set(talkingHead.items.map(\.id)).subtracting(cut))
        #expect(edit.usedItems(of: secondAngle).isEmpty)
    }

    @Test func clipStartTimesRunBackToBack() throws {
        var edit = try wholeTake()
        try edit.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        let starts = edit.clipStartTimes
        #expect(starts.count == 2)
        #expect(starts[0] == 0)
        #expect(starts[1].isClose(to: shortPauseEdge))
    }

    // MARK: - B-roll and layouts

    @Test func brollIsAnchoredToWords() throws {
        var edit = try wholeTake()
        let broll = try edit.placeOverlay(.source(SourceID(number: 9)), over: range(w(8), w(11)), sourceIn: 2, transcripts: transcripts)
        #expect(edit.overlays == [broll])
        #expect(broll.over == .words(range(w(8), w(11))))
        #expect(broll.id == ClipID(number: 2), "B-roll clips share the clip id counter.")
    }

    @Test func brollOverUnknownWordsIsRejected() throws {
        var edit = try wholeTake()
        #expect(throws: EditError.unknownItem(w(50))) {
            try edit.placeOverlay(.source(SourceID(number: 9)), over: range(w(1), w(50)), transcripts: transcripts)
        }
    }

    @Test func setLayoutChangesOneClip() throws {
        var edit = try wholeTake()
        try edit.setLayout(.card(.bubble), for: ClipID(number: 1))
        #expect(edit.main[0].layout == .card(.bubble))
        #expect(throws: EditError.unknownClip(ClipID(number: 7))) { try edit.setLayout(.screen, for: ClipID(number: 7)) }
    }

    @Test func errorsSayWhatToDo() {
        #expect(EditError.rangeOutOfOrder(range(w(5), w(2))).errorDescription?.contains("Give the earlier id first") == true)
        #expect(EditError.unknownItem(w(9)).errorDescription?.contains("w_9") == true)
    }
}

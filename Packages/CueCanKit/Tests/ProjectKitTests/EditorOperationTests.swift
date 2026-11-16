import Foundation
import Testing
@testable import ProjectKit

/// The editor's operations (docs/decisions.md, 54 to 61): cuts by time, edges anywhere, hand-placed edges,
/// overlays, freezes, speed, word fixes, the look, redo and the editor's state.
@Suite struct EditorOperationTests {
    let transcripts = TranscriptIndex([talkingHead, secondAngle])
    let source = SourceID(number: 1)

    /// All of `talkingHead` as one clip, 0–7 s.
    func wholeTake() throws -> Edit {
        var edit = Edit()
        try edit.addClip(range(s(1), s(5)), transcripts: transcripts, snapping: testPads)
        return edit
    }

    func played(_ edit: Edit) -> [[Double]] {
        edit.main.map { [($0.playedRange.start * 1000).rounded() / 1000, ($0.playedRange.end * 1000).rounded() / 1000] }
    }

    // MARK: - Cuts by time

    @Test func cuttingATimelineRangeTakesOutExactlyThat() throws {
        var edit = try wholeTake()
        // Most of the long pause s_4 (4.1–5.6): keep its first and last tenth.
        let removed = try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5))
        #expect(removed.isClose(to: 1.3))
        #expect(played(edit) == [[0, 4.2], [5.5, 7]])
        #expect(edit.main[1].id == ClipID(number: 2), "The piece after a middle cut is a new clip.")
    }

    @Test func aTimelineCutOnlyRemovesWhatPlaysThere() throws {
        var edit = try wholeTake()
        // The same words played twice: a cut by time takes out only the second.
        try edit.addClip(range(w(1), w(2)), transcripts: transcripts, snapping: testPads)
        let before = edit.main[0]
        try edit.cut(timeline: TimeRange(start: 7, end: 7.5))
        #expect(edit.main[0] == before)
        #expect(edit.main.count == 2)
    }

    @Test func aTimelineCutAcrossTwoClipsTrimsBoth() throws {
        var edit = try wholeTake()
        try edit.cut(timeline: TimeRange(start: 2, end: 3))
        try edit.cut(timeline: TimeRange(start: 1.5, end: 2.5))
        #expect(played(edit) == [[0, 1.5], [3.5, 7]])
    }

    @Test func edgesMadeByHandAreMarked() throws {
        var edit = try wholeTake()
        try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5), byHand: true)
        #expect(edit.main[0].endPlacedByHand)
        #expect(edit.main[1].startPlacedByHand)
        #expect(!edit.main[0].startPlacedByHand, "An edge that didn't move isn't marked.")
    }

    @Test func cutsByTimeOutsideTheEditAreRefused() throws {
        var edit = try wholeTake()
        #expect(throws: EditError.timeOutsideEdit(8, duration: 7)) { try edit.cut(timeline: TimeRange(start: 8, end: 9)) }
        #expect(throws: EditError.invalidTimeRange(TimeRange(start: 3, end: 2))) { try edit.cut(timeline: TimeRange(start: 3, end: 2)) }
    }

    @Test func keepingBySourceTimePutsItBack() throws {
        var edit = try wholeTake()
        try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5))
        let added = try edit.keep(source: source, range: TimeRange(start: 4, end: 6), sourceDuration: 7)
        #expect(added.isClose(to: 1.3))
        #expect(played(edit) == [[0, 7]])
    }

    @Test func cuttingBySourceTimeMatchesACutByID() throws {
        var byTime = try wholeTake()
        var byID = try wholeTake()
        let time = try CutPointSnapper(transcript: talkingHead, settings: testPads).timeRange(for: range(w(4), w(7)))
        try byTime.cut(source: source, range: time)
        try byID.cut(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        #expect(byTime.main == byID.main)
    }

    // MARK: - The blade and edges

    @Test func theBladeSplitsAtAnExactTime() throws {
        var edit = try wholeTake()
        let parts = try edit.split(at: 4.85, byHand: true)
        #expect(parts.first.playedRange.end.isClose(to: 4.85))
        #expect(parts.second.startsAtSplit)
        #expect(parts.second.startPlacedByHand)
        #expect(edit.duration.isClose(to: 7), "A split removes nothing.")
        #expect(throws: EditError.splitTooCloseToEdge(0, ClipID(number: 1))) { try edit.split(at: 0) }
    }

    @Test func anEdgeCanGoAnywhereAndOutwardBringsBackWhatWasCut() throws {
        var edit = try wholeTake()
        try edit.cut(range(s(1), w(2)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main[0].playedRange.start > 1.8)
        // Dragging the start out keeps what was cut, to an exact time between words.
        try edit.setEdge(.start, of: ClipID(number: 1), to: 1.42, sourceDuration: 7, byHand: true)
        #expect(edit.main[0].playedRange.start.isClose(to: 1.42))
        #expect(edit.main[0].startNudge == 0)
        #expect(edit.main[0].startPlacedByHand)
        #expect(throws: EditError.edgeOutsideRecording(ClipID(number: 1))) {
            try edit.setEdge(.end, of: ClipID(number: 1), to: 9, sourceDuration: 7)
        }
        #expect(throws: EditError.edgeLeavesTooLittle(ClipID(number: 1))) {
            try edit.setEdge(.end, of: ClipID(number: 1), to: 1.43, sourceDuration: 7)
        }
    }

    @Test func trimmingToThePlayheadGoesThroughSpeed() throws {
        var edit = try wholeTake()
        try edit.setSpeed(try #require(ClipSpeed(rate: 2)), for: ClipID(number: 1))
        #expect(edit.duration.isClose(to: 3.5))
        try edit.trim(.end, toTimeline: 1, sourceDuration: 7)
        #expect(edit.main[0].playedRange.end.isClose(to: 2), "One second at 2× is two seconds of source.")
    }

    @Test func trimmingIntoASplitNeighbourMovesTheSplit() throws {
        var edit = try wholeTake()
        try edit.split(at: 3.5)
        // The second part's start, earlier: the first part gives way, so nothing plays twice.
        try edit.setEdge(.start, of: ClipID(number: 2), to: 3, sourceDuration: 7, byHand: true)
        #expect(edit.main[0].playedRange.end.isClose(to: 3))
        #expect(edit.main[1].playedRange.start.isClose(to: 3))
        #expect(edit.main[0].endPlacedByHand && edit.main[1].startPlacedByHand)
        #expect(edit.main[1].startsAtSplit)
        #expect(edit.duration.isClose(to: 7))
        // The first part's end, later: the second gives way.
        try edit.setEdge(.end, of: ClipID(number: 1), to: 4, sourceDuration: 7, byHand: true)
        #expect(edit.main[1].playedRange.start.isClose(to: 4))
        #expect(edit.duration.isClose(to: 7))
        #expect(edit.isRollable(.start, of: ClipID(number: 2)) && edit.isRollable(.end, of: ClipID(number: 1)))
        // Inward is a trim: it cuts, and the join no longer rolls.
        try edit.setEdge(.start, of: ClipID(number: 2), to: 4.5, sourceDuration: 7, byHand: true)
        #expect(edit.main[0].playedRange.end.isClose(to: 4))
        #expect(!edit.main[1].startsAtSplit)
        #expect(!edit.isRollable(.start, of: ClipID(number: 2)))
        #expect(edit.outwardLimit(.start, of: ClipID(number: 2)) == 4)
        #expect(edit.duration.isClose(to: 6.5))
        // Back out past the first part's end, it stops where that ends, and the two meet and roll again.
        try edit.setEdge(.start, of: ClipID(number: 2), to: 3.8, sourceDuration: 7, byHand: true)
        #expect(edit.main[0].playedRange.end.isClose(to: 4))
        #expect(edit.main[1].playedRange.start.isClose(to: 4))
        #expect(edit.main[1].startsAtSplit)
        #expect(edit.isRollable(.start, of: ClipID(number: 2)))
        // The first part's end trimmed, then pulled back past the second's start: it stops there too.
        try edit.setEdge(.end, of: ClipID(number: 1), to: 3.5, sourceDuration: 7, byHand: true)
        #expect(!edit.isRollable(.end, of: ClipID(number: 1)))
        try edit.setEdge(.end, of: ClipID(number: 1), to: 6, sourceDuration: 7, byHand: true)
        #expect(edit.main[0].playedRange.end.isClose(to: 4))
        #expect(edit.main[1].playedRange.start.isClose(to: 4))
        // Not so far that the first part disappears.
        #expect(throws: EditError.edgeLeavesTooLittle(ClipID(number: 1))) {
            try edit.setEdge(.start, of: ClipID(number: 2), to: 0, sourceDuration: 7)
        }
    }

    @Test func clipsFromDifferentRecordingsNeverRoll() throws {
        var edit = Edit()
        edit.main = [
            Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 2),
            Clip(id: ClipID(number: 2), source: SourceID(number: 2), sourceIn: 2, sourceOut: 4),
        ]
        #expect(!edit.joinRolls(after: 0))
        #expect(edit.outwardLimit(.start, of: ClipID(number: 2)) == nil)
        try edit.setEdge(.start, of: ClipID(number: 2), to: 1, sourceDuration: 4)
        #expect(edit.main[0].playedRange.end == 2)
        #expect(edit.main[1].playedRange.start == 1)
    }

    @Test func removingAClipClosesTheGap() throws {
        var edit = try wholeTake()
        try edit.split(at: 3.5)
        try edit.removeClip(ClipID(number: 1))
        #expect(edit.main.count == 1)
        #expect(!edit.main[0].startsAtSplit)
        #expect(edit.clipStartTimes == [0])
    }

    // MARK: - Hand-placed edges and broad passes

    @Test func removeSilencesLeavesHandPlacedEdgesAlone() throws {
        var edit = try wholeTake()
        // The creator trimmed into the long pause by hand, keeping 0.6 s of it before "This".
        try edit.cut(timeline: TimeRange(start: 4.1, end: 5.0), byHand: true)
        let handStart = try #require(edit.main.first { $0.startPlacedByHand })
        let handEnd = try #require(edit.main.first { $0.endPlacedByHand })
        let shortened = try edit.removeSilences(longerThan: 0.5, leaving: 0.3, transcripts: transcripts, snapping: testPads)
        #expect(edit.main.first { $0.startPlacedByHand }?.playedRange.start == handStart.playedRange.start, "The hand-placed start stays put.")
        #expect(edit.main.first { $0.endPlacedByHand }?.playedRange.end == handEnd.playedRange.end, "So does the hand-placed end.")
        #expect(shortened == 2, "The pauses s_1 and s_2, which no hand-placed edge touches, were shortened; s_4 wasn't.")
    }

    @Test func claudesTimeCutsDontMarkEdges() throws {
        var edit = try wholeTake()
        try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5))
        #expect(!edit.main[0].endPlacedByHand)
        #expect(try edit.removeSilences(longerThan: 0.5, leaving: 0.3, transcripts: transcripts, snapping: testPads) >= 1)
    }

    // MARK: - Speed and freezes

    @Test func speedScalesTheTimelineAndMapsTimesThroughIt() throws {
        var edit = try wholeTake()
        try edit.split(at: 4.2)
        try edit.split(at: 5.5)
        try edit.setSpeed(try #require(ClipSpeed(rate: 4)), for: edit.main[1].id)
        #expect(edit.main[1].speed.sound == .muted, "Above 2× is muted unless asked.")
        #expect(edit.duration.isClose(to: 4.2 + 1.3 / 4 + 1.5))
        let placed = try #require(edit.placement(at: 4.3))
        #expect(placed.sourceTime(at: 4.3).isClose(to: 4.2 + 0.1 * 4))
        #expect(edit.sourceTime(at: 4.2 + 1.3 / 4 + 0.1)?.time.isClose(to: 5.6) == true)
        #expect(ClipSpeed(rate: 3) == nil)
        #expect(ClipSpeed(rate: 1.5)?.sound == .pitchKept)
    }

    @Test func aFreezeIsKeptInSourceTimeAndFollowsCuts() throws {
        var edit = try wholeTake()
        let made = try edit.freeze(timeline: TimeRange(start: 5, end: 6))
        #expect(made.count == 1)
        #expect(made[0].range == TimeRange(start: 5, end: 6))
        #expect(made[0].frame == 5, "It holds the frame at its start.")
        // Cutting earlier moves the timeline, not the freeze.
        try edit.cut(timeline: TimeRange(start: 1, end: 2))
        #expect(edit.freezes[0].range == TimeRange(start: 5, end: 6))
        #expect(edit.freeze(holding: 5.5, in: source)?.id == made[0].id)
        #expect(edit.freeze(holding: 6.5, in: source) == nil)
    }

    @Test func aFreezeAcrossACutHoldsOneFrame() throws {
        var edit = try wholeTake()
        try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5))
        let made = try edit.freeze(timeline: TimeRange(start: 4, end: 4.5))
        #expect(made.count == 2)
        #expect(made.allSatisfy { $0.frame == 4 })
        #expect(edit.removeFreezes(overlapping: TimeRange(start: 4.1, end: 4.15)) == 1)
    }

    @Test func freezeIDsShareTheCounter() throws {
        var edit = try wholeTake()
        let freeze = try #require(try edit.freeze(timeline: TimeRange(start: 1, end: 2)).first)
        #expect(freeze.id == FreezeID(number: 2))
        #expect(edit.makeClipID() == ClipID(number: 3))
        try edit.removeFreeze(freeze.id)
        #expect(edit.freezes.isEmpty)
        #expect(throws: EditError.unknownFreeze(freeze.id)) { try edit.removeFreeze(freeze.id) }
    }

    // MARK: - Overlays

    @Test func anOverlayOverTimeIsAnchoredToSourceTime() throws {
        var edit = try wholeTake()
        let overlay = try edit.placeOverlay(.file(at: URL(filePath: "/tmp/shot.png")), overTimeline: TimeRange(start: 4.2, end: 5.5), placement: .inScreensPlace)
        #expect(overlay.isStill)
        #expect(!overlay.playsSound)
        #expect(overlay.over == .time(source: source, range: TimeRange(start: 4.2, end: 5.5)))
        try edit.cut(timeline: TimeRange(start: 0, end: 1))
        let pieces = edit.timelinePieces(of: overlay, transcripts: transcripts)
        #expect(pieces.count == 1)
        #expect(pieces[0].timeline.start.isClose(to: 3.2))
    }

    @Test func anOverlayOverWordsThatPlayTwiceShowsTwiceAndKeepsPace() throws {
        var edit = try wholeTake()
        let overlay = try edit.placeOverlay(.file(at: URL(filePath: "/tmp/clip.mov")), over: range(w(4), w(9)), sourceIn: 2, transcripts: transcripts)
        #expect(overlay.isMuted, "A video overlay starts muted.")
        try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5))
        let pieces = edit.timelinePieces(of: overlay, transcripts: TranscriptIndex([talkingHead]), snapping: .default)
        #expect(pieces.count == 2, "Either side of the cut.")
        #expect(pieces[0].timeline.end.isClose(to: pieces[1].timeline.start), "They meet on the timeline.")
        #expect(pieces[1].mediaStart.isClose(to: pieces[0].mediaStart + pieces[0].timeline.duration), "The video keeps pace across the cut.")
        try edit.moveOverlay(overlay.id, overTimeline: TimeRange(start: 1, end: 2))
        #expect(edit.overlays[0].over == .time(source: source, range: TimeRange(start: 1, end: 2)))
        try edit.updateOverlay(overlay.id) { $0.isMuted = false }
        #expect(edit.overlays[0].playsSound)
        try edit.removeOverlay(overlay.id)
        #expect(throws: EditError.unknownOverlay(overlay.id)) { try edit.removeOverlay(overlay.id) }
    }

    // MARK: - Words

    @Test func aFixReplacesTheWords() throws {
        var edit = try wholeTake()
        var next = 100
        // Untimed: one word over the replaced words' time, which cuts as a whole.
        let untimed = try edit.fixWords(range(w(1), w(2)), as: " Hi   there! ", timings: nil, transcripts: transcripts, nextWordNumber: &next)
        #expect(!untimed.isTimed && next == 101)
        var fixed = TranscriptIndex([talkingHead], fixes: edit.fixes)
        var words = try #require(fixed[source]).words
        #expect(words.first == Word(id: WordID(number: 100), text: "Hi there!", start: 1.0, end: 1.8))
        #expect(!words.contains { $0.id == WordID(number: 1) || $0.id == WordID(number: 2) }, "The old words are gone, not hidden.")
        #expect(fixed.untimedWords == [WordID(number: 100)])
        #expect(talkingHead.words[0].text == "Hello", "The transcript file keeps the model's output underneath.")

        // Timed: each word gets its own id and times, and a fix of a fix works the same way.
        let timings = [AlignedWord(text: "Hi", start: 1.02, end: 1.3), AlignedWord(text: "there!", start: 1.35, end: 1.75)]
        let timed = try edit.fixWords(range(w(100), w(100)), as: "Hi there!", timings: timings, transcripts: fixed, nextWordNumber: &next)
        #expect(timed.isTimed && timed.words.map(\.id) == [WordID(number: 101), WordID(number: 102)])
        fixed = TranscriptIndex([talkingHead], fixes: edit.fixes)
        words = try #require(fixed[source]).words
        #expect(words.prefix(2).map(\.text) == ["Hi", "there!"])
        #expect(fixed.untimedWords.isEmpty)
        // The new words cut by id like any others.
        _ = try edit.cut(range(w(102), w(102)), transcripts: fixed)
        #expect(edit.main.count == 2)

        #expect(throws: EditError.wordsNotWords(range(s(1), w(3)))) {
            try edit.fixWords(range(s(1), w(3)), as: "x", timings: nil, transcripts: fixed, nextWordNumber: &next)
        }
        #expect(throws: EditError.emptyFix(range(w(3), w(3)))) {
            try edit.fixWords(range(w(3), w(3)), as: "  ", timings: nil, transcripts: fixed, nextWordNumber: &next)
        }
    }

    @Test func timingsThatDontMatchTheTextLeaveTheFixUntimed() throws {
        var edit = try wholeTake()
        var next = 100
        let fix = try edit.fixWords(range(w(4), w(5)), as: "These are", timings: [AlignedWord(text: "Those", start: 3, end: 3.2)],
                                    transcripts: transcripts, nextWordNumber: &next)
        #expect(!fix.isTimed && fix.words.map(\.text) == ["These are"])
    }

    @Test func aFixKeepsTheSilencesClearOfItsWords() throws {
        // A timed word reaching into the silence before it shortens that silence; one inside the run that a
        // new word covers goes; a fix never crosses the words either side.
        let fix = WordFix(replaces: range(w(3), w(4)), words: [
            Word(id: WordID(number: 50), text: "So", start: 2.5, end: 2.95),
            Word(id: WordID(number: 51), text: "this", start: 2.95, end: 3.4),
        ], isTimed: true)
        let fixed = try #require(talkingHead.applying(fix))
        #expect(fixed.items.map(\.id.description).prefix(7) == ["s_1", "w_1", "w_2", "s_2", "w_50", "w_51", "w_5"])
        #expect(fixed.silences[1] == Silence(id: SilenceID(number: 2), start: 1.8, end: 2.5))
        #expect(!fixed.items.contains { $0.id == .silence(SilenceID(number: 3)) })
        let wide = WordFix(replaces: range(w(3), w(3)), words: [Word(id: WordID(number: 52), text: "Um,", start: 1.0, end: 3.6)], isTimed: true)
        let clamped = try #require(talkingHead.applying(wide)).words.first { $0.id == WordID(number: 52) }
        #expect(clamped?.start == 1.8 && clamped?.end == 3.0, "Kept between the words either side.")
        #expect(talkingHead.applying(WordFix(replaces: range(w(99), w(99)), words: fix.words, isTimed: true)) == nil)
    }

    @Test func spellingsSkipWordsAFixReplaced() throws {
        var edit = try wholeTake()
        var next = 100
        try edit.fixWords(range(w(4), w(4)), as: "these", timings: nil, transcripts: transcripts, nextWordNumber: &next)
        let fixed = try #require(TranscriptIndex([talkingHead], fixes: edit.fixes)[source])
        let spellings = VocabularySpellings(source: source, terms: ["Thisis", "Taking"], spellings: [
            .init(words: range(w(4), w(5)), text: "Thisis"), .init(words: range(w(10), w(11)), text: "Taking"),
        ])
        let texts = edit.exportTexts(of: fixed, spellings: spellings)
        #expect(texts[WordID(number: 100)] == "these")
        #expect(texts[WordID(number: 5)] == "is")
        #expect(texts[WordID(number: 10)] == "Taking" && texts[WordID(number: 11)] == "")
    }

    // MARK: - The look and levels

    @Test func theLookKeepsItsValuesInRange() throws {
        var look = OutputLook(background: "abc")
        #expect(look.background == "#AABBCC")
        look.background = "not a colour"
        #expect(look.background == "#AABBCC", "A bad colour is refused, keeping the last.")
        // The inset is a fraction of the short side: whole pixels at 720p, 1080p and 4K (docs/decisions.md, 66).
        #expect(OutputLook.Inset.allCases.map { $0.fraction * 1080 } == [0, 30, 60, 90])
        #expect(OutputLook.Inset.allCases.allSatisfy { ($0.fraction * 720).rounded() == $0.fraction * 720 })
        #expect(OutputLook.plain.inset == .medium && OutputLook.plain.rounded, "A first take starts at Inset M, rounded.")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OutputLook.self, from: Data(#"{"background":"red"}"#.utf8)) }
        #expect(SoundLevel.volume(forGain: SoundLevel.range.lowerBound) == 0)
        #expect(SoundLevel.volume(forGain: -6).isClose(to: 0.501, tolerance: 0.001))
    }

    // MARK: - Snapping

    @Test func snappingSticksToSilenceEdgesAndClipEdgesButNotWordBoundaries() throws {
        var edit = try wholeTake()
        let snapper = EditSnapper(transcripts: TranscriptIndex([talkingHead]), snapping: testPads)
        let cutPoints = CutPointSnapper(transcript: talkingHead, settings: testPads)
        let silenceEdge = cutPoints.boundary(before: 10)  // "take." into the long pause
        let near = snapper.snap(silenceEdge + 0.03, in: edit, tolerance: 0.1)
        #expect(near.time.isClose(to: silenceEdge))
        #expect(near.target == .silenceEdge)
        #expect(snapper.snap(silenceEdge + 0.03, in: edit, tolerance: 0.01).target == nil, "Off by more than the tolerance: it lands where it is.")
        // Between "is" and "the" there's no silence: the model's word times aren't a snap point (decision 74).
        let wordGap = cutPoints.boundary(before: 7)
        #expect(snapper.snap(wordGap + 0.01, in: edit, tolerance: 0.05).target == nil)
        try edit.cut(timeline: TimeRange(start: 4.2, end: 5.5))
        #expect(snapper.snap(4.21, in: edit, tolerance: 0.05).time.isClose(to: 4.2))
    }

    @Test func withNothingElseInReachSnappingSticksToTheBottomOfADip() throws {
        let edit = try wholeTake()
        // Loud speech at −20 dB with one 30 ms dip to −40 dB at 3.5 s, between "is" and "the".
        var levels = [Double](repeating: -20, count: 700)
        for frame in 349...351 { levels[frame] = frame == 350 ? -40 : -32 }
        let envelope = SoundEnvelope(levels: levels, frameDuration: 0.01)
        let snapper = EditSnapper(transcripts: TranscriptIndex([talkingHead]), envelopes: [talkingHead.source: envelope], snapping: testPads)
        let snapped = snapper.snap(3.48, in: edit, tolerance: 0.05)
        #expect(snapped.target == .quietPoint)
        #expect(snapped.time.isClose(to: 3.505))
        #expect(snapper.snap(3.3, in: edit, tolerance: 0.05).target == nil, "Steady sound has no dip.")
        // A dragged edge finds it in source time too.
        let edge = try #require(snapper.snap(sourceTime: 3.46, in: talkingHead.source, tolerance: 0.05))
        #expect(edge.target == .quietPoint && edge.time.isClose(to: 3.505))
    }

    // MARK: - Redo and editor state

    @Test func undoThenRedoPutsTheChangeBackAsANewChange() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "Redo")
        try folder.updateEdit(author: .app, reason: "Gutter") { $0.look.rounded = false }
        #expect(!folder.canRedo)
        try folder.undo()
        #expect(folder.canRedo)
        #expect(folder.redoReason == "Gutter")
        let redone = try folder.redo(author: .app)
        #expect(redone.look.rounded == false)
        #expect(!folder.canRedo)
        #expect(try folder.history.entries().last?.reason == "Redo: Gutter")
        // Undo, then any other change, and there's nothing to redo.
        try folder.undo()
        try folder.updateEdit(author: .agent("Claude"), reason: "Corners") { $0.look.rounded = false }
        #expect(!folder.canRedo)
        #expect(throws: ProjectFolderError.nothingToRedo) { try folder.redo(author: .app) }
    }

    @Test func editorStateIsSavedBesideTheEditWithoutHistory() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "State")
        #expect(try folder.loadEditorState() == nil)
        let state = EditorState(playhead: 12.5, selection: .init(clips: [ClipID(number: 3)]), markIn: 10, markOut: 14, markers: [3], editRevision: 2, updatedAt: Date(timeIntervalSince1970: 100))
        try folder.saveEditorState(state)
        #expect(try folder.loadEditorState() == state)
        #expect(state.markedRange == TimeRange(start: 10, end: 14))
        #expect(try folder.history.entries().isEmpty, "The editor's state isn't part of the edit.")
    }
}

@Suite struct WholeTakeTests {
    @Test func theWholeSourceIsOneClip() throws {
        var project = Project(title: "Whole take")
        let source = project.addSource(name: "Take", origin: .recorded, tracks: [
            SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: 12, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
            SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), startOffset: 0.02, media: MediaInfo(duration: 12.1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
        ])
        var edit = Edit()
        #expect(edit.addWholeSource(source) != nil)
        #expect(edit.main.count == 1)
        // To the end of the track that ends first, where every track still has something (docs/decisions.md, 87).
        #expect(edit.main[0].playedRange == TimeRange(start: 0, end: 12))
    }
}

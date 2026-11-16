import Foundation
import Testing
import ProjectKit
@testable import RenderKit

@Suite struct EditTimelineTests {
    @Test func clipsPlayBackToBack() {
        let edit = Edit(main: [clip(1, 1.0, 1.8), clip(2, 3.0, 4.1)])
        let timeline = EditTimeline(edit: edit, transcripts: TranscriptIndex([speech]))
        #expect(timeline.clips.map(\.timeline.start).elementsEqual([0, 0.8]) { $0.isClose(to: $1) })
        #expect(timeline.clips.map(\.timeline.end).elementsEqual([0.8, 1.9]) { $0.isClose(to: $1) })
        #expect(timeline.segments.count == 2)
        #expect(timeline.duration.isClose(to: 1.9))
        #expect(timeline.timelineTimes(of: 3.5, in: SourceID(number: 1)).first?.isClose(to: 1.3) == true)
        #expect(timeline.timelineTimes(of: 2.0, in: SourceID(number: 1)).isEmpty, "Cut out.")
    }

    @Test func brollFollowsItsWordsAndSplitsTheStretches() throws {
        var edit = Edit(main: [clip(1, 0.95, 4.2)])
        edit.overlays = [Overlay(id: ClipID(number: 9), media: .source(SourceID(number: 2)), sourceIn: 5, over: .words(ItemRange(first: w(4), last: w(5))))]
        let timeline = EditTimeline(edit: edit, transcripts: TranscriptIndex([speech]))
        let broll = try #require(timeline.overlays.first)
        // "this is" snaps to 2.95…3.5ish; on the timeline that's 0.95 s earlier.
        #expect(broll.timeline.start > 1.9 && broll.timeline.start < 2.1)
        #expect(timeline.segments.map(\.overlayIndices) == [[], [0], []])
        #expect(broll.mediaTime(at: broll.timeline.start + 1).isClose(to: 6))
    }

    @Test func brollStaysOffAClipBetweenItsWords() throws {
        // "Hello there." plays, then 5 s of another source, then "this is the take." The B-roll over all of
        // those words must not cover the other source's clip.
        var edit = Edit(main: [clip(1, 0.95, 1.9), clip(2, source: 3, 0, 5), clip(3, 2.95, 4.2)])
        edit.overlays = [Overlay(id: ClipID(number: 9), media: .source(SourceID(number: 2)), sourceIn: 10, over: .words(ItemRange(first: w(1), last: w(7))))]
        let timeline = EditTimeline(edit: edit, transcripts: TranscriptIndex([speech]))
        #expect(timeline.overlays.count == 2)
        let other = timeline.clips[1].timeline
        #expect(timeline.overlays.allSatisfy { !$0.timeline.overlaps(other) })
        // The second stretch picks up where the first left off: the overlay keeps pace with the timeline.
        let first = try #require(timeline.overlays.first)
        let second = try #require(timeline.overlays.last)
        #expect(second.mediaStart.isClose(to: 10 + first.timeline.duration))
        #expect(timeline.segments.map(\.overlayIndices) == [[0], [], [1]])
    }

    @Test func brollOverWordsThatWereCutIsLeftOut() {
        var edit = Edit(main: [clip(1, 0.95, 1.9)])
        edit.overlays = [Overlay(id: ClipID(number: 9), media: .source(SourceID(number: 2)), over: .words(ItemRange(first: w(4), last: w(5))))]
        #expect(EditTimeline(edit: edit, transcripts: TranscriptIndex([speech])).overlays.isEmpty)
    }

    @Test func aSpedUpClipIsShorterAndMapsItsTimes() throws {
        var edit = Edit(main: [clip(1, 1.0, 1.8), clip(2, 3.0, 5.0)])
        edit.main[1].speed = try #require(ClipSpeed(rate: 4))
        let timeline = EditTimeline(edit: edit, transcripts: TranscriptIndex([speech]))
        #expect(timeline.duration.isClose(to: 0.8 + 0.5))
        #expect(timeline.timelineTimes(of: 4.0, in: SourceID(number: 1)).first?.isClose(to: 0.8 + 0.25) == true)
        #expect(timeline.clips[1].sourceTime(at: 1.05).isClose(to: 4.0))
    }

    @Test func syncedSourcesConvertThroughTheirReference() {
        var project = Project(title: "Sync")
        project.addSource(name: "Camera", origin: .imported, tracks: [])
        project.addSource(name: "Mic", origin: .imported, tracks: [], sync: SourceSync(reference: SourceID(number: 1), offset: 2, method: .waveform))
        project.addSource(name: "Angle", origin: .imported, tracks: [], sync: SourceSync(reference: SourceID(number: 1), offset: -1, method: .waveform))
        let clock = SourceClock(project: project)
        #expect(clock.time(10, in: SourceID(number: 2), as: SourceID(number: 1)) == 12)
        #expect(clock.time(12, in: SourceID(number: 1), as: SourceID(number: 2)) == 10)
        #expect(clock.time(10, in: SourceID(number: 2), as: SourceID(number: 3)) == 13)
    }
}

@Suite struct CaptionTests {
    let transcripts = TranscriptIndex([speech])

    @Test func captionsFollowTheCutAndSkipFillers() {
        let edit = Edit(main: [clip(1, 0.95, 1.9), clip(2, 2.55, 4.2)])
        let timeline = EditTimeline(edit: edit, transcripts: transcripts)
        let cues = CaptionBuilder.cues(edit: edit, timeline: timeline, transcripts: transcripts)
        #expect(cues.map(\.text) == ["Hello there.", "this is the take."])
        let first = cues[1].words[0]
        // "this" starts at 3.0 in the source: 0.45 s into the second clip, which starts at 0.95.
        #expect(first.timeline.start.isClose(to: 0.95 + 0.45))
    }

    @Test func wordFixesAndSpeedReachTheSRT() throws {
        var edit = Edit(main: [clip(1, 2.95, 4.2)])
        edit.main[0].speed = try #require(ClipSpeed(rate: 2))
        var next = 100
        try edit.fixWords(ItemRange(first: w(4), last: w(5)), as: "This’s", timings: nil, transcripts: transcripts, nextWordNumber: &next)
        let fixed = TranscriptIndex(Array(transcripts.transcripts.values), fixes: edit.fixes)
        let timeline = EditTimeline(edit: edit, transcripts: fixed)
        let cues = CaptionBuilder.cues(edit: edit, timeline: timeline, transcripts: fixed)
        #expect(cues.map(\.text) == ["This’s the take."])
        #expect(cues[0].words.last?.timeline.end.isClose(to: (4.1 - 2.95) / 2) == true, "Times go through the speed.")
        #expect(TextTranscriptWriter.text(cues) == "This’s the take.\n")
    }

    @Test func theTextTranscriptBreaksParagraphsAtLongPauses() {
        let cue = { (text: String, start: Double) in CaptionCue(words: [.init(text: text, timeline: TimeRange(start: start, end: start + 1))], timeline: TimeRange(start: start, end: start + 1)) }
        #expect(TextTranscriptWriter.text([cue("One.", 0), cue("Two.", 1.5), cue("Three.", 10)]) == "One. Two.\n\nThree.\n")
    }

    @Test func spellingsReplaceTheWordsTheyCover() {
        let spellings = VocabularySpellings(
            source: SourceID(number: 1),
            terms: ["Hello there"],
            spellings: [.init(words: ItemRange(first: w(1), last: w(2)), text: "Hellothere.")]
        )
        let edit = Edit(main: [clip(1, 0.95, 1.9)])
        let timeline = EditTimeline(edit: edit, transcripts: transcripts)
        let cues = CaptionBuilder.cues(edit: edit, timeline: timeline, transcripts: transcripts, spellings: [SourceID(number: 1): spellings])
        #expect(cues.map(\.text) == ["Hellothere."])
    }

    @Test func srtTimesAreHoursMinutesSecondsAndMilliseconds() {
        let cue = CaptionCue(words: [.init(text: "Hi", timeline: TimeRange(start: 3661.5, end: 3662.25))], timeline: TimeRange(start: 3661.5, end: 3662.25))
        #expect(SRTWriter.srt([cue, cue]) == "1\n01:01:01,500 --> 01:01:02,250\nHi\n\n2\n01:01:01,500 --> 01:01:02,250\nHi\n")
    }
}

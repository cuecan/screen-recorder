import Foundation
import Testing
@testable import ProjectKit

/// The transcript in the inspector (docs/ui.md, "The transcript in the inspector").
struct TranscriptReadingTests {
    let source = SourceID(number: 1)
    let transcripts = TranscriptIndex([talkingHead])

    func clip(_ number: Int, _ start: TimeInterval, _ end: TimeInterval) -> Clip {
        Clip(id: ClipID(number: number), source: source, sourceIn: start, sourceOut: end)
    }

    func texts(_ reading: TranscriptReading) -> [String] {
        reading.tokens.map { token in
            switch token.kind {
            case .word(let text): token.isCut ? "-\(text)" : text
            case .silence(let length): String(format: "[%.1f]", length)
            }
        }
    }

    @Test func editShowsOnlyWhatPlaysWithTheSilencesWorthSeeing() {
        // Cut from "Um," to the first "take.": the second clip starts in the 1.5 s silence.
        let edit = Edit(main: [clip(1, 0, 2.55), clip(2, 4.2, 7)])
        let reading = TranscriptReading(mode: .edit, placements: edit.placements, sources: [source], transcripts: transcripts)
        #expect(texts(reading) == ["Hello", "there.", "[1.4]", "This", "is", "the", "take."],
                "Silences under a second don't show, and a silence counts only what plays of it.")
        #expect(reading.blocks.count == 1)
        #expect(reading.tokens[3].timeline?.start.isClose(to: 2.55 + 1.4) == true)
    }

    @Test func fullShowsEverythingWithWhatWasCutMarked() {
        let edit = Edit(main: [clip(1, 0, 2.55), clip(2, 4.2, 7)])
        let reading = TranscriptReading(mode: .full, placements: edit.placements, sources: [source], transcripts: transcripts)
        #expect(texts(reading) == ["Hello", "there.", "-Um,", "-this", "-is", "-the", "-take.", "[1.5]", "This", "is", "the", "take."])
        // Put back what's picked: one run, since it's one stretch of one recording.
        let picked = reading.itemRanges(from: reading.tokens[2].id, through: reading.tokens[6].id)
        #expect(picked == [range(w(3), w(7))])
    }

    @Test func aLongSilenceGetsItsOwnBlock() {
        let transcript = TranscriptBuilder.make(source: source, duration: 12, [
            .word("One.", 0, 0.5), .silence(0.5, 6), .word("Two.", 6, 6.5), .silence(6.5, 12),
        ])
        let reading = TranscriptReading(mode: .full, placements: [], sources: [source], transcripts: TranscriptIndex([transcript]))
        #expect(reading.blocks.count == 4)
        guard case .silence(let block) = reading.blocks[1] else { Issue.record("Expected a silence block"); return }
        #expect(block.silenceLength == 5.5 && block.isCut)
        guard case .paragraph(let after) = reading.blocks[2] else { Issue.record("Expected a paragraph"); return }
        #expect(after.tokens.map(\.text) == ["Two."], "The words after a long silence start a new paragraph.")
    }

    @Test func anotherAppStartsAParagraphAndAnotherWindowTicksTheRail() {
        let fronts = [
            ScreenFront(start: 0, app: "Xcode", bundleID: "com.apple.dt.Xcode", window: "Edit.swift"),
            ScreenFront(start: 1.4, app: "Xcode", bundleID: "com.apple.dt.Xcode", window: "Clip.swift"),
            ScreenFront(start: 3.0, app: "Safari", bundleID: "com.apple.Safari", window: "Docs"),
        ]
        let edit = Edit(main: [clip(1, 0, 7)])
        let reading = TranscriptReading(mode: .edit, placements: edit.placements, sources: [source], transcripts: transcripts,
                                        fronts: [source: fronts])
        let paragraphs = reading.blocks.compactMap { block -> TranscriptReading.Paragraph? in
            if case .paragraph(let paragraph) = block { paragraph } else { nil }
        }
        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].front?.app == "Xcode" && paragraphs[1].front?.app == "Safari")
        #expect(paragraphs[0].tokens.map(\.text) == ["Hello", "there.", "Um,"])
        #expect(paragraphs[0].tokens[1].windowChange?.window == "Clip.swift")
        #expect(paragraphs[0].tokens[0].windowChange == nil && paragraphs[1].tokens[0].windowChange == nil)
    }

    @Test func fixesReadAsTheTranscriptsOwnWords() throws {
        var edit = Edit(main: [clip(1, 0, 7)])
        var next = 100
        try edit.fixWords(range(w(4), w(5)), as: "This's", timings: nil, transcripts: transcripts, nextWordNumber: &next)
        let fixed = TranscriptIndex([talkingHead], fixes: edit.fixes)
        let reading = TranscriptReading(mode: .edit, placements: edit.placements, sources: [source], transcripts: fixed)
        #expect(Array(texts(reading).prefix(6)) == ["Hello", "there.", "Um,", "This's", "the", "take."])
        #expect(reading.tokens[3].isUntimed)
        #expect(reading.wordRange(from: reading.tokens[2].id, through: reading.tokens[4].id) == range(w(3), w(6)))
    }

    @Test func picksAcrossClipsPlayedOutOfOrderAreCutAsSeparateRuns() {
        // The second half plays first: one run per clip, each in the recording's own order.
        let edit = Edit(main: [clip(1, 4.2, 7), clip(2, 0, 2.55)])
        let reading = TranscriptReading(mode: .edit, placements: edit.placements, sources: [source], transcripts: transcripts)
        #expect(texts(reading) == ["This", "is", "the", "take.", "[1.0]", "Hello", "there."])
        let tokens = reading.tokens
        let ranges = reading.itemRanges(from: tokens[3].id, through: tokens[6].id)
        #expect(ranges == [range(w(11), w(11)), range(s(1), w(2))])
        #expect(reading.wordRange(from: tokens[3].id, through: tokens[6].id) == nil, "A fix is one run of words.")
    }
}

/// Settling what was in front, so a quick switch leaves no mark.
struct ScreenFrontTests {
    func event(_ t: TimeInterval, _ type: ScreenLog.EventType, app: String? = nil, window: String? = nil) -> ScreenLog.Event {
        var event = ScreenLog.Event(t: t, type: type)
        event.app = app
        event.bundleID = app.map { "com.example.\($0)" }
        event.window = window
        return event
    }

    @Test func aQuickSwitchAwayAndBackLeavesNoMark() {
        let fronts = ScreenFront.settled(from: [
            event(0, .app, app: "Xcode", window: "Edit.swift"),
            event(10, .app, app: "Slack", window: "general"),
            event(10.8, .app, app: "Xcode", window: "Edit.swift"),
            event(20, .app, app: "Safari", window: "Docs"),
            event(20.5, .window, window: "Page 2"),
            event(21, .window, window: "Page 3"),
        ], until: 30)
        #expect(fronts.map(\.app) == ["Xcode", "Safari"])
        #expect(fronts[1].window == "Page 3" && fronts[1].start == 21, "A browser shows only the pages it stayed on.")
        #expect(ScreenFront.front(at: 15, in: fronts)?.app == "Xcode")
    }

    @Test func aWindowChangeThatStaysCounts() {
        let fronts = ScreenFront.settled(from: [
            event(0, .app, app: "Xcode", window: "Edit.swift"),
            event(5, .window, window: "Clip.swift"),
            event(6, .cursor),
        ], until: 9)
        #expect(fronts.map(\.window) == ["Edit.swift", "Clip.swift"])
        #expect(fronts[1].app == "Xcode")
        #expect(ScreenFront.settled(from: [event(0, .app, app: "Xcode")], until: 1).count == 1, "A short take still has what was in front.")
    }
}

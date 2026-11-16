import Foundation
import Testing
@testable import ProjectKit

struct TranscriptFixingTests {
    @Test func mutationsUseTheCurrentEditsCorrectedTranscript() throws {
        let folder = try ProjectFolder.create(at: makeTemporaryFolder(), title: "Correction snapshot")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let project = try folder.updateProject { $0.addSource(name: "Fixture", origin: .recorded, tracks: []) }
        let source = try #require(project.sources.first?.id)
        try folder.addTranscript(TranscriptDraft(engine: "fixture", silenceDetector: "fixture", language: "en", audioDuration: 3,
            items: [.word(.init(text: "Hello", start: 1, end: 1.5))]), for: source)
        try folder.updateEdit(author: .app, reason: "Fixture") {
            $0.main = [Clip(id: ClipID(number: 1), source: source, sourceIn: 0, sourceOut: 3)]
        }
        let (_, fix) = try folder.fixWords(range(w(1), w(1)), as: "Hi", timings: nil, author: .app, reason: "Fix")
        let corrected = try #require(fix.words.first?.id)
        try folder.updateEdit(author: .app, reason: "Cut corrected words") { edit, transcripts in
            #expect(transcripts[source]?.words.map(\.id) == [corrected])
            #expect(transcripts.source(of: w(1)) == nil)
            try edit.cut(ItemRange(.word(corrected)), transcripts: transcripts)
        }
        #expect(try folder.loadEdit().duration < 3)
    }

    @Test func alternativesAndRetakesDoNotSurviveAFixInsideTheirRanges() throws {
        var transcript = talkingHead
        transcript.alternatives = [WordAlternative(words: range(w(3), w(7)), text: "Another reading"),
                                   WordAlternative(words: range(w(8), w(11)), text: "Unchanged")]
        transcript.retakes = [Retake(attempt: range(w(3), w(7)), redoneAs: range(w(8), w(11)))]
        let fix = WordFix(replaces: range(w(4), w(5)), words: [
            Word(id: WordID(number: 100), text: "these were", start: 3, end: 3.5),
        ], isTimed: false)
        let fixed = try #require(transcript.applying(fix))
        #expect(fixed.alternatives.map(\.text) == ["Unchanged"])
        #expect(fixed.retakes.isEmpty)
    }

    @Test func identicalRequestsStillHaveDistinctLifetimes() {
        var fixing = TranscriptFixing()
        let old = fixing.begin(range(w(1), w(2)), text: "Hello there")
        let next = fixing.begin(old.range, text: old.text)
        #expect(old.id != next.id)
        #expect(!fixing.contains(old))
        fixing.finish(old)
        #expect(fixing.pending == next)
        fixing.cancel()
        fixing.finish(next)
        #expect(fixing.state == .idle)
    }

    @Test func aFixKeepsOverlaysWhoseWordAndSilenceAnchorsAreRetired() throws {
        var edit = Edit(main: [Clip(id: ClipID(number: 1), source: talkingHead.source, sourceIn: 0, sourceOut: 7)])
        let transcripts = TranscriptIndex([talkingHead])
        for anchor in [range(w(3), w(4)), range(s(3), w(7)), range(w(8), w(11))] {
            try edit.placeOverlay(.file(at: .init(filePath: "/tmp/fixture.png")), over: anchor, transcripts: transcripts)
        }
        let before = edit.overlays.map { edit.timelinePieces(of: $0, transcripts: transcripts).map(\.timeline) }
        var next = 100
        try edit.fixWords(range(w(3), w(4)), as: "So this", timings: [
            AlignedWord(text: "So", start: 2.6, end: 2.95), AlignedWord(text: "this", start: 2.95, end: 3.3),
        ], transcripts: transcripts, nextWordNumber: &next)
        let fixed = TranscriptIndex([talkingHead], fixes: edit.fixes)
        let after = edit.overlays.map { edit.timelinePieces(of: $0, transcripts: fixed).map(\.timeline) }
        #expect(before == after)
        #expect(edit.overlays[2].over == .words(range(w(8), w(11))), "Unchanged anchors keep following their words.")
        let snapshot = try JSONEncoder().encode(edit)
        #expect(try JSONDecoder().decode(Edit.self, from: snapshot) == edit)
    }
}

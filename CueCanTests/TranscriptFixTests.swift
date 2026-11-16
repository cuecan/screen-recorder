import AppKit
import ProjectKit
import Testing
@testable import CueCan

@MainActor
struct TranscriptFixTests {
    @Test func deletingInsideAWordTargetsThatWordRatherThanItsNeighbour() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let inputs = try RenderInputsForTest(folder)
        let reading = TranscriptReading(mode: .edit, placements: inputs.edit.placements, sources: [inputs.source], transcripts: inputs.transcripts)
        let document = TranscriptDocument(reading: reading, pending: nil, transcripts: inputs.transcripts)
        let first = try #require(document.pieces.first)
        let last = try #require(document.pieces.last)
        #expect(document.word(before: last.range.location + 1)?.token.id == last.token.id)
        #expect(document.word(after: first.range.location + 1)?.token.id == first.token.id)
        #expect(document.word(before: last.range.location)?.token.id == first.token.id)
        #expect(document.word(after: first.range.upperBound)?.token.id == last.token.id)
    }

    @Test func supersededAlignmentCannotSaveOrClearTheNewRequest() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let gate = FixGate()
        let model = EditorModel(folder: folder, alignFix: { _, _, _ in await gate.wait() })
        model.loadForPreview()
        let range = ItemRange(.word(WordID(number: 1)))
        model.fixText("First", for: range)
        let first = try #require(model.fixTask)
        try await waitUntil { gate.started == 1 }
        model.fixText("Second", for: range)
        let second = try #require(model.fixTask)
        try await waitUntil { gate.started == 2 }
        gate.release(0)
        await first.value
        #expect(try folder.loadEdit().fixes.isEmpty)
        #expect(model.pendingFix?.text == "Second")
        gate.release(1)
        await second.value
        #expect(try folder.loadTranscripts().transcripts.values.first?.words.first?.text == "Second")
        #expect(try folder.loadEdit().fixes.count == 1)
        #expect(model.pendingFix == nil)
    }

    @Test func undoInvalidatesAnAlignmentEvenIfTheWorkerIgnoresCancellation() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let gate = FixGate()
        let model = EditorModel(folder: folder, alignFix: { _, _, _ in await gate.wait() })
        model.loadForPreview()
        model.fixText("Later", for: ItemRange(.word(WordID(number: 1))))
        let task = try #require(model.fixTask)
        try await waitUntil { gate.started == 1 }
        model.undo()
        #expect(model.pendingFix == nil)
        gate.release(0)
        await task.value
        #expect(try folder.loadEdit().fixes.isEmpty)
    }

    @Test func aPendingCorrectionAppearsOncePerOccurrenceAcrossParagraphs() throws {
        let folder = try makeFolder(wordCount: 62)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let inputs = try RenderInputsForTest(folder)
        var fixing = TranscriptFixing()
        let pending = fixing.begin(ItemRange(first: .word(WordID(number: 59)), last: .word(WordID(number: 62))), text: "Replacement")
        let reading = TranscriptReading(mode: .edit, placements: inputs.edit.placements, sources: [inputs.source], transcripts: inputs.transcripts)
        #expect(reading.blocks.count == 2)
        let document = TranscriptDocument(reading: reading, pending: pending, transcripts: inputs.transcripts)
        #expect(document.text.string.components(separatedBy: "Replacement").count - 1 == 1)
        #expect(document.pendingRanges.count == 1)
    }

    private func makeFolder(wordCount: Int = 2) throws -> ProjectFolder {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-transcript-review-\(UUID())")
        let folder = try ProjectFolder.create(at: url, title: "Transcript regression")
        let project = try folder.updateProject { project in
            project.addSource(name: "Fixture", origin: .recorded, tracks: [
                SourceTrack(kind: .camera, file: .inProject("recordings/missing.mov"),
                    media: MediaInfo(duration: Double(wordCount), video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1")))
            ])
        }
        let source = try #require(project.sources.first)
        try folder.addTranscript(TranscriptDraft(engine: "fixture", silenceDetector: "fixture", language: "en", audioDuration: Double(wordCount),
            items: (0..<wordCount).map { .word(.init(text: $0 == 59 ? "End." : "word\($0)", start: Double($0), end: Double($0) + 0.5)) }), for: source.id)
        try folder.updateEdit(author: .app, reason: "Fixture") { $0.addWholeSource(source) }
        return folder
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while !condition() {
            guard clock.now < deadline else { throw NSError(domain: "TranscriptFixTests", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct RenderInputsForTest {
        let edit: Edit
        let transcripts: TranscriptIndex
        let source: SourceID
        init(_ folder: ProjectFolder) throws {
            edit = try folder.loadEdit()
            transcripts = try folder.loadTranscripts()
            source = try #require(try folder.loadProject().sources.first?.id)
        }
    }
}

@MainActor
private final class FixGate {
    private var continuations: [Int: CheckedContinuation<[AlignedWord]?, Never>] = [:]
    private(set) var started = 0
    func wait() async -> [AlignedWord]? {
        let index = started
        started += 1
        return await withCheckedContinuation { continuations[index] = $0 }
    }
    func release(_ index: Int) { continuations.removeValue(forKey: index)?.resume(returning: nil) }
}

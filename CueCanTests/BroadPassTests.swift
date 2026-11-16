import Foundation
import ProjectKit
import Testing
@testable import CueCan

/// Remove Silences from the editor, without an agent: the selected clips or the whole
/// edit, edges placed by hand left alone, and each run one History entry by the app that one undo reverses.
@MainActor
struct BroadPassTests {
    /// A 10 s take: words, a 2 s pause (2–4), a filler (5–5.3), words, a 1.5 s pause (7–8.5), words.
    private func makeFolder() throws -> ProjectFolder {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-broad-pass-\(UUID().uuidString)")
        let folder = try ProjectFolder.create(at: url, title: "Broad passes")
        let project = try folder.updateProject { project in
            project.addSource(name: "Take", origin: .recorded, tracks: [
                SourceTrack(kind: .camera, file: .inProject("recordings/fixture.mov"), startOffset: 0,
                            media: MediaInfo(duration: 10, video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1"))),
            ])
        }
        let source = try #require(project.sources.first)
        _ = try folder.addTranscript(TranscriptDraft(engine: "test", silenceDetector: "test", language: "en", audioDuration: 10, items: [
            .word(.init(text: "One", start: 0, end: 2)), .silence(start: 2, end: 4),
            .word(.init(text: "two", start: 4, end: 5)), .word(.init(text: "um", start: 5, end: 5.3, isFiller: true)),
            .word(.init(text: "three", start: 5.3, end: 7)), .silence(start: 7, end: 8.5),
            .word(.init(text: "four.", start: 8.5, end: 10)),
        ]), for: source.id)
        try folder.updateEdit(author: .system("Test"), reason: "Fixture") { $0.addWholeSource(source) }
        return folder
    }

    /// The editor's preferences for a test, so nothing reads or changes the app's own.
    private let preferences: UserDefaults = {
        let name = "cuecan-broad-pass-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }()

    @Test func removeSilencesUsesTheThresholdSetInTheTranscriptAndRemembersIt() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder, preferences: preferences)
        model.loadForPreview()
        #expect(model.silenceThreshold == Edit.defaultSilenceThreshold)
        model.silenceThreshold = 1.84
        #expect(model.silenceThreshold == 1.8, "Kept to a tenth of a second.")
        model.removeSilences()
        // Only the 2 s pause is over 1.8 s; the 1.5 s one stays.
        #expect(abs(try folder.loadEdit().duration - (10 - 1.7)) < 0.01)
        #expect(model.notice == "Shortened 1 pause to 0.3 s.")
        #expect(try folder.history.entries().last?.reason == "Shortened pauses over 1.8 s to 0.3 s")
        // The next project opens with it.
        #expect(EditorModel(folder: folder, preferences: preferences).silenceThreshold == 1.8)
        model.silenceThreshold = 0
        #expect(model.silenceThreshold == Edit.silenceThresholds.lowerBound)
    }

    @Test func removeSilencesOnTheWholeEditIsOneChangeByTheApp() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder, preferences: preferences)
        model.loadForPreview()
        let before = try folder.loadEdit()
        let entries = try folder.history.entries().count
        model.removeSilences()
        let after = try folder.loadEdit()
        // Both pauses are over 0.7 s; each leaves 0.3 s.
        #expect(abs(after.duration - (10 - 1.7 - 1.2)) < 0.01, "\(after.duration)")
        #expect(model.notice == "Shortened 2 pauses to 0.3 s.")
        let history = try folder.history.entries()
        #expect(history.count == entries + 1)
        #expect(history.last?.author == .app)
        model.undo()
        #expect(try folder.loadEdit().main == before.main, "One undo puts it all back.")
    }

    @Test func removeSilencesLeavesAPauseAtAnEdgePlacedByHand() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        // The creator ended the clip by hand inside the second pause.
        try folder.updateEdit(author: .app, reason: "Trim") { edit in
            try edit.setEdge(.end, of: edit.main[0].id, to: 8, sourceDuration: 10, byHand: true)
        }
        let model = EditorModel(folder: folder, preferences: preferences)
        model.loadForPreview()
        model.removeSilences()
        let edit = try folder.loadEdit()
        #expect(edit.main.last?.playedRange.end == 8, "The hand-placed end stays put.")
        #expect(model.notice == "Shortened 1 pause to 0.3 s.")
    }
}

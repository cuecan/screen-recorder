import Foundation
import Testing
@testable import ProjectKit

@Suite struct ProjectFolderTests {
    func makeProject() throws -> ProjectFolder {
        let url = try makeTemporaryFolder().appending(path: "2026-11-06 Editing with Claude")
        return try ProjectFolder.create(at: url, title: "Editing with Claude")
    }

    func draft(_ words: [String], duration: TimeInterval = 10) -> TranscriptDraft {
        var items: [TranscriptDraft.DraftItem] = [.silence(start: 0, end: 0.5)]
        for (index, text) in words.enumerated() {
            let start = 0.5 + Double(index)
            items.append(.word(.init(text: text, start: start, end: start + 0.6)))
            items.append(.silence(start: start + 0.6, end: start + 1))
        }
        return TranscriptDraft(engine: "test", silenceDetector: "energy", language: "en", audioDuration: duration, items: items)
    }

    /// Adds a recorded source and returns its id.
    func addSource(to folder: ProjectFolder, name: String = "Recording") throws -> SourceID {
        var id: SourceID?
        try folder.updateProject { project in
            id = project.addSource(name: name, origin: .recorded, tracks: []).id
        }
        return try #require(id)
    }

    // MARK: - Creating and opening

    @Test func createMakesTheFolderLayout() throws {
        let folder = try makeProject()
        for subfolder in ProjectFolder.Folder.allCases {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: folder.url(for: subfolder).path(percentEncoded: false), isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
        #expect(try folder.loadProject().title == "Editing with Claude")
        #expect(try folder.loadEdit() == Edit())
    }

    @Test func openingReadsAnExistingProject() throws {
        let folder = try makeProject()
        let reopened = try ProjectFolder(opening: folder.url)
        #expect(try reopened.loadProject().id == folder.loadProject().id)
    }

    /// Format 7 brought captions (docs/decisions.md, 80); a format-6 edit says it's older rather than naming
    /// the missing key (65).
    @Test func aFormatSixEditSaysItsOlder() throws {
        let folder = try makeProject()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.editFileURL)) as? [String: Any])
        json["formatVersion"] = 6
        json["captions"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: folder.editFileURL)
        let reopened = try ProjectFolder(opening: folder.url)
        #expect(throws: ProjectFolderError.olderFormat(folder.editFileURL, 6)) { try reopened.loadEdit() }
    }

    @Test func openingAFolderWithoutAProjectFails() throws {
        let url = try makeTemporaryFolder()
        #expect {
            try ProjectFolder(opening: url)
        } throws: { error in
            guard case .notAProject = error as? ProjectFolderError else { return false }
            return true
        }
    }

    @Test func creatingOverAnExistingProjectFails() throws {
        let folder = try makeProject()
        #expect(throws: ProjectFolderError.alreadyAProject(folder.url)) {
            try ProjectFolder.create(at: folder.url, title: "Again")
        }
    }

    @Test func aNewerFormatIsRefusedWithAClearMessage() throws {
        let folder = try makeProject()
        var project = try folder.loadProject()
        project.formatVersion = Project.currentFormatVersion + 1
        try folder.write(project, to: folder.projectFileURL)
        #expect(throws: ProjectFolderError.newerFormat(folder.projectFileURL, Project.currentFormatVersion + 1)) {
            try ProjectFolder(opening: folder.url)
        }
        let message = ProjectFolderError.newerFormat(folder.projectFileURL, 2).errorDescription ?? ""
        #expect(message.contains("Update CueCan"))
    }

    /// An older project can lack a key the current one needs, such as a track's capture rate. It still says
    /// it's an older format, not which key is missing.
    @Test func anOlderFormatSaysSoEvenWhenItDoesNotDecode() throws {
        let folder = try makeProject()
        try Data(#"{ "formatVersion": 2, "sources": [{ "tracks": [{ "media": { "video": { "frameRate": 31 } } }] }] }"#.utf8)
            .write(to: folder.projectFileURL)
        #expect(throws: ProjectFolderError.olderFormat(folder.projectFileURL, 2)) { try ProjectFolder(opening: folder.url) }
    }

    @Test func damagedJSONIsReportedAsDamaged() throws {
        let folder = try makeProject()
        try Data("{ not json".utf8).write(to: folder.editFileURL)
        #expect {
            try folder.loadEdit()
        } throws: { error in
            guard case .unreadable(let url, _) = error as? ProjectFolderError else { return false }
            return url == folder.editFileURL
        }
    }

    @Test func filesArePrettyAndSorted() throws {
        let folder = try makeProject()
        let text = try String(contentsOf: folder.projectFileURL, encoding: .utf8)
        #expect(text.contains("\n  \"createdAt\""))
        #expect(text.firstRange(of: "createdAt")?.lowerBound ?? text.endIndex < text.firstRange(of: "title")?.lowerBound ?? text.startIndex)
    }

    // MARK: - Transcripts

    @Test func transcriptIDsAreUniqueAcrossSources() throws {
        let folder = try makeProject()
        let first = try addSource(to: folder, name: "Main camera")
        let second = try addSource(to: folder, name: "Second angle")

        let one = try folder.addTranscript(draft(["one", "two"]), for: first)
        let two = try folder.addTranscript(draft(["three"]), for: second)

        #expect(one.items.map(\.id) == [s(1), w(1), s(2), w(2), s(3)])
        #expect(two.items.map(\.id) == [s(4), w(3), s(5)])

        let project = try folder.loadProject()
        #expect(project.nextWordNumber == 4)
        #expect(project.nextSilenceNumber == 6)
        #expect(project.source(first)?.transcriptFile == "src_1.json")
        #expect(try folder.loadTranscript(for: first) == one)

        let index = try folder.loadTranscripts()
        #expect(try index.transcript(containing: ItemRange(w(3))).source == second)
    }

    @Test func aTranscriptIsNeverReplaced() throws {
        let folder = try makeProject()
        let source = try addSource(to: folder)
        try folder.addTranscript(draft(["one"]), for: source)
        #expect(throws: ProjectFolderError.alreadyTranscribed(source)) {
            try folder.addTranscript(draft(["other"]), for: source)
        }
        #expect(try folder.loadProject().nextWordNumber == 2, "A refused transcript doesn't use up ids.")
    }

    @Test func transcribingAnUnknownSourceFails() throws {
        let folder = try makeProject()
        #expect(throws: EditError.unknownSource(SourceID(number: 5))) {
            try folder.addTranscript(draft(["one"]), for: SourceID(number: 5))
        }
    }

    @Test func untranscribedSourceHasNoTranscript() throws {
        let folder = try makeProject()
        let source = try addSource(to: folder)
        #expect(try folder.loadTranscript(for: source) == nil)
    }

    // MARK: - History and undo

    @Test func everyChangeIsSnapshottedFirst() throws {
        let folder = try makeProject()
        let source = try addSource(to: folder)
        try folder.addTranscript(draft(["one", "two", "three"]), for: source)
        let transcripts = try folder.loadTranscripts()

        let afterAdd = try folder.updateEdit(author: .agent("Claude"), reason: "Add the take") { edit in
            try edit.addClip(range(s(1), s(4)), transcripts: transcripts)
        }
        let afterCut = try folder.updateEdit(author: .agent("Claude"), reason: "Cut “two”") { edit in
            try edit.cut(ItemRange(w(2)), transcripts: transcripts)
        }

        #expect(afterAdd.revision == 1)
        #expect(afterCut.revision == 2)
        #expect(try folder.loadEdit() == afterCut)

        let entries = try folder.history.entries()
        #expect(entries.map(\.sequence) == [1, 2])
        #expect(entries.map(\.reason) == ["Add the take", "Cut “two”"])
        #expect(entries.map(\.author) == [.agent("Claude"), .agent("Claude")])
        #expect(entries[0].edit == Edit(), "Each snapshot is the edit before its change.")
        #expect(entries[1].edit == afterAdd)
    }

    @Test func aChangeThatChangesNothingIsNotSaved() throws {
        let folder = try makeProject()
        let edit = try folder.updateEdit(author: .app, reason: "Nothing") { _ in }
        #expect(edit.revision == 0)
        #expect(try folder.history.entries().isEmpty)
    }

    @Test func aFailedChangeLeavesTheEditAlone() throws {
        let folder = try makeProject()
        #expect(throws: EditError.unknownItem(w(1))) {
            try folder.updateEdit(author: .agent("Claude"), reason: "Bad") { edit in
                try edit.cut(ItemRange(w(1)), transcripts: TranscriptIndex([]))
            }
        }
        #expect(try folder.loadEdit() == Edit())
        #expect(try folder.history.entries().isEmpty)
    }

    @Test func undoPutsBackTheEditBeforeTheLatestChange() throws {
        let folder = try makeProject()
        let first = try folder.updateEdit(author: .app, reason: "Captions on") { $0.look.rounded = false }
        try folder.updateEdit(author: .agent("Claude"), reason: "Loudness") { $0.audio.loudnessTarget = -16 }

        let restored = try folder.undo()
        #expect(restored.look.rounded == false)
        #expect(restored.audio.loudnessTarget == -14)
        #expect(restored.revision == 3, "Undo moves the revision forward so watchers see it.")
        #expect(try folder.loadEdit() == restored)
        #expect(try folder.history.entries().map(\.sequence) == [1])

        var expected = first
        expected.revision = 3
        #expect(restored == expected)
    }

    @Test func undoThroughAChangeUndoesEverythingAfterIt() throws {
        let folder = try makeProject()
        try folder.updateEdit(author: .app, reason: "1") { $0.audio.loudnessTarget = -15 }
        try folder.updateEdit(author: .app, reason: "2") { $0.audio.loudnessTarget = -16 }
        try folder.updateEdit(author: .app, reason: "3") { $0.audio.loudnessTarget = -17 }

        let restored = try folder.undo(through: 2)
        #expect(restored.audio.loudnessTarget == -15)
        #expect(try folder.history.entries().map(\.sequence) == [1])
        #expect(folder.redoReason == "2; 3")
    }

    @Test func undoReadsOnlyTheSnapshotsBeingRestored() throws {
        let folder = try makeProject()
        try folder.updateEdit(author: .app, reason: "Earlier") { $0.audio.loudnessTarget = -15 }
        try folder.updateEdit(author: .app, reason: "Latest") { $0.audio.loudnessTarget = -16 }
        let earlier = folder.url(for: .history).appending(path: "000001.json")
        let unreadable = Data("Unreadable earlier snapshot".utf8)
        try unreadable.write(to: earlier)

        let restored = try folder.undo()
        #expect(restored.audio.loudnessTarget == -15)
        #expect(folder.redoReason == "Latest")
        #expect(try Data(contentsOf: earlier) == unreadable)
        let redone = try folder.redo(author: .app)
        #expect(redone.audio.loudnessTarget == -16)
    }

    @Test func undoneSnapshotsAreKeptAndNumbersAreNeverReused() throws {
        let folder = try makeProject()
        try folder.updateEdit(author: .app, reason: "1") { $0.audio.loudnessTarget = -15 }
        try folder.updateEdit(author: .app, reason: "2") { $0.audio.loudnessTarget = -16 }
        try folder.undo()
        try folder.updateEdit(author: .app, reason: "3") { $0.audio.loudnessTarget = -18 }

        #expect(try folder.history.entries().map(\.sequence) == [1, 3])
        let undone = folder.url(for: .history).appending(path: "undone")
        let moved = try FileManager.default.contentsOfDirectory(atPath: undone.path(percentEncoded: false))
        #expect(moved.count == 1)
        #expect(moved == ["000002.json"])
    }

    @Test func clipIDsAreNeverReusedAfterAnUndo() throws {
        let folder = try makeProject()
        let source = try addSource(to: folder)
        try folder.addTranscript(draft(["one", "two", "three"]), for: source)
        let transcripts = try folder.loadTranscripts()
        let added = try folder.updateEdit(author: .agent("Claude"), reason: "Add") { edit in
            try edit.addClip(range(s(1), s(4)), transcripts: transcripts)
        }
        #expect(added.main.map(\.id) == [ClipID(number: 1)])
        try folder.undo()
        let again = try folder.updateEdit(author: .agent("Claude"), reason: "Add again") { edit in
            try edit.addClip(range(s(1), s(4)), transcripts: transcripts)
        }
        #expect(again.main.map(\.id) == [ClipID(number: 2)], "c_1 named a clip that was undone, so it isn't reused.")
    }

    /// The editor reads the files under the project's lock and decodes them afterwards.
    @Test func storedHistoryDecodesToTheSameEntriesOldestFirst() throws {
        let folder = try ProjectFolder.create(at: makeTemporaryFolder().appending(path: "Stored"), title: "Stored")
        #expect(try folder.history.storedEntries().isEmpty, "A new project has no history.")
        for seconds in [2.0, 5.0, 9.0] {
            try folder.updateEdit(author: .app, reason: "Clip \(Int(seconds))") {
                $0.main = [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: seconds)]
            }
        }
        let decoded = try folder.history.storedEntries().map { try EditHistory.entry(decoding: $0) }
        #expect(decoded == (try folder.history.entries()))
        #expect(decoded.map(\.reason) == ["Clip 2", "Clip 5", "Clip 9"])
        try folder.undo()
        #expect(try folder.history.storedEntries().count == 2, "An undone snapshot is no longer in effect.")
    }

    @Test func undoWithNoHistoryFails() throws {
        let folder = try makeProject()
        #expect(throws: ProjectFolderError.nothingToUndo) { try folder.undo() }
        #expect(throws: ProjectFolderError.unknownHistoryEntry(4)) { try folder.undo(through: 4) }
    }

    /// The app and the CLI write the same folder: concurrent read-modify-writes must not lose changes.
    @Test func concurrentWritersDoNotLoseChanges() async throws {
        let folder = try makeProject()
        let writers = 24
        try await withThrowingTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    // A second ProjectFolder value for the same URL, as another process would have.
                    let other = try ProjectFolder(opening: folder.url)
                    try other.updateEdit(author: .system("writer \(writer)"), reason: "Bump") { edit in
                        edit.audio.loudnessTarget -= 1
                    }
                }
            }
            try await group.waitForAll()
        }
        let edit = try folder.loadEdit()
        #expect(edit.revision == writers)
        #expect(edit.audio.loudnessTarget == -14 - Double(writers))
        #expect(try folder.history.entries().count == writers)
    }
}

struct CleanedAudioFileTests {
    @Test func aNewCleaningRemovesAllButTheFilesStillNamed() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "Cleaned")
        let track = SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"),
                                media: MediaInfo(duration: 1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
        try folder.updateProject { $0.addSource(name: "Take", origin: .recorded, tracks: [track]) }
        let source = SourceID(number: 1)
        let settings = try folder.loadEdit().audio.settings(for: source)
        let audio = folder.url(for: .audio)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        func clean(_ purpose: CleanedAudio.Purpose = .preview) throws -> String {
            let name = CleanedAudio.newFileName(for: source, settings: settings)
            try Data().write(to: audio.appending(path: name))
            try folder.saveCleanedAudio(CleanedAudio(source: source, settings: settings, file: name, original: track.file), purpose: purpose)
            return name
        }
        let first = try clean()
        let handoff = try clean(.handoff)
        let second = try clean()
        let third = try clean()
        let other = audio.appending(path: "src_10-natural75-off.wav")
        try Data().write(to: other)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: audio.path(percentEncoded: false)).filter { $0.hasSuffix(".wav") })
        // The current preview file, the one it replaced, and the hand-off's stay; the oldest goes.
        #expect(left == [third, second, handoff, other.lastPathComponent])
        #expect(!left.contains(first))
    }

    @Test func aNewTakeStartsWithTheLastProjectsLook() throws {
        let root = try makeTemporaryFolder()
        let library = ProjectLibrary(projectsFolder: root, recentsFile: root.appending(path: "recent.json"))
        #expect(library.lastLook() == nil, "No project yet.")
        func clip(_ side: OutputLook.CameraSide, seconds: Double) -> Clip {
            Clip(id: ClipID(number: Int(seconds)), source: SourceID(number: 1), sourceIn: 0, sourceOut: seconds,
                 look: ClipLook(cameraSide: side))
        }
        let older = try ProjectFolder.create(at: root.appending(path: "Older"), title: "Older")
        try older.updateEdit(author: .app, reason: "Look") { $0.main = [clip(.standard, seconds: 5)]; $0.look.inset = .small }
        let newer = try ProjectFolder.create(at: root.appending(path: "Newer"), title: "Newer")
        try newer.updateEdit(author: .app, reason: "Look") {
            $0.main = [clip(.standard, seconds: 2), clip(.flipped, seconds: 9)]
            $0.look.background = "#FFFFFF"
            $0.look.inset = .large
        }
        #expect(library.lastLook()?.background == "#FFFFFF")
        #expect(library.lastLook()?.inset == .large, "The most recently changed project's inset (docs/decisions.md, 66 and 86).")
        #expect(library.lastLook()?.cameraSide == .flipped, "The camera side most of it plays (68).")
    }
}

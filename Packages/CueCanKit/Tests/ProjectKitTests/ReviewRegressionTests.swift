import Foundation
import Testing
@testable import ProjectKit

@Suite struct ReviewRegressionTests {
    @Test func adjacentWordClipsNeverRepeatTheShortPause() throws {
        var edit = Edit()
        let transcripts = TranscriptIndex([talkingHead])
        try edit.addClip(range(w(1), w(3)), transcripts: transcripts, snapping: testPads)
        try edit.addClip(range(w(4), w(7)), transcripts: transcripts, snapping: testPads)
        #expect(edit.main[0].playedRange.end == edit.main[1].playedRange.start)
        #expect(!edit.main[0].playedRange.overlaps(edit.main[1].playedRange))
    }

    @Test func clipIDsAccountForInitialAndSubsequentlyInsertedClips() {
        let source = SourceID(number: 1)
        var edit = Edit(main: [Clip(id: ClipID(number: 8), source: source, sourceIn: 0, sourceOut: 1)])
        #expect(edit.makeClipID() == ClipID(number: 9))
        edit.overlays.append(Overlay(id: ClipID(number: 20), media: .source(source), over: .words(ItemRange(w(1)))))
        #expect(edit.makeClipID() == ClipID(number: 21))
    }

    @Test func emptyRangesDoNotSplitClips() {
        let range = TimeRange(start: 0, end: 2)
        #expect(!range.overlaps(TimeRange(start: 1, end: 1)))
        #expect(range.subtracting(TimeRange(start: 1, end: 1)) == [range])
    }

    @Test func unencodableEditDoesNotCreateAnUndoEntry() throws {
        let folder = try ProjectFolderTests().makeProject()
        #expect(throws: (any Error).self) {
            try folder.updateEdit(author: .system("Test"), reason: "Invalid") { $0.audio.loudnessTarget = .nan }
        }
        #expect(try folder.loadEdit() == Edit())
        #expect(try folder.history.entries().isEmpty)
    }

    @Test func transcriptFileWithoutMetadataIsNeverOverwritten() throws {
        let fixture = ProjectFolderTests()
        let folder = try fixture.makeProject()
        let source = try fixture.addSource(to: folder)
        let original = try folder.addTranscript(fixture.draft(["original"]), for: source)
        try folder.updateProject { $0.sources[0].transcriptFile = nil }
        #expect(throws: ProjectFolderError.alreadyTranscribed(source)) {
            try folder.addTranscript(fixture.draft(["replacement"]), for: source)
        }
        #expect(try folder.loadTranscript(for: source) == original)
    }

    @Test(arguments: [false, true])
    func interruptedTranscriptCommitRecoversBeforeAllocatingMoreIDs(fileAlreadyWritten: Bool) throws {
        let fixture = ProjectFolderTests()
        let folder = try fixture.makeProject()
        let source = try fixture.addSource(to: folder)
        var project = try folder.loadProject()
        let assigned = fixture.draft(["original"]).assigningIDs(source: source, firstWordNumber: 1, firstSilenceNumber: 1)
        project.nextWordNumber = assigned.nextWordNumber
        project.nextSilenceNumber = assigned.nextSilenceNumber
        project.sources[0].transcriptFile = "src_1.json"
        try folder.write(ProjectMutation.transcript(project: project, transcript: assigned.transcript),
                         to: folder.url.appending(path: ".pending-mutation.json"))
        if fileAlreadyWritten { try folder.write(assigned.transcript, to: folder.transcriptURL(for: source)) }
        let recovered = try ProjectFolder(opening: folder.url)
        #expect(try recovered.loadTranscript(for: source)?.text == "original")
        let second = try fixture.addSource(to: recovered)
        let transcript = try recovered.addTranscript(fixture.draft(["next"]), for: second)
        #expect(transcript.words.first?.id == WordID(number: 2))
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: ".pending-mutation.json").path))
    }

    @Test(arguments: [false, true])
    func interruptedEditCommitDoesNotDuplicateHistory(snapshotAlreadyWritten: Bool) throws {
        let folder = try ProjectFolderTests().makeProject()
        let before = try folder.loadEdit()
        var after = before
        after.look.rounded = false
        after.revision = 1
        let entry = try folder.history.prepare(snapshotOf: before, author: .system("Test"), reason: "Captions")
        try folder.write(ProjectMutation.history(edit: after, action: .append(entry), redo: []), to: folder.url.appending(path: ".pending-mutation.json"))
        if snapshotAlreadyWritten { try folder.history.save(entry) }
        let reopened = try ProjectFolder(opening: folder.url)
        #expect(try reopened.loadEdit() == after)
        #expect(try reopened.history.entries().count == 1)
        #expect(try reopened.undo().look.rounded == true)
    }

    @Test func interruptedUndoFinishesArchivingHistory() throws {
        let folder = try ProjectFolderTests().makeProject()
        try folder.updateEdit(author: .system("Test"), reason: "Captions") { $0.look.rounded = false }
        var restored = Edit()
        restored.revision = 2
        try folder.write(ProjectMutation.history(edit: restored, action: .undo(through: 1), redo: [RedoStack.Entry(edit: try folder.loadEdit(), reason: "Undo", author: .system("Test"))]), to: folder.url.appending(path: ".pending-mutation.json"))
        try folder.write(restored, to: folder.editFileURL)
        let reopened = try ProjectFolder(opening: folder.url)
        #expect(try reopened.loadEdit() == restored)
        #expect(try reopened.history.entries().isEmpty)
        #expect(throws: ProjectFolderError.nothingToUndo) { try reopened.undo() }
        #expect(try reopened.redo(author: .system("Test")).look.rounded == false)
    }

    @Test func aLostCounterNeverReusesAnUndoneNumber() throws {
        let folder = try ProjectFolderTests().makeProject()
        try folder.updateEdit(author: .system("Test"), reason: "Captions on") { $0.look.rounded = false }
        try folder.updateEdit(author: .system("Test"), reason: "Captions off") { $0.look.rounded = true }
        try folder.undo()
        // A copy that skips hidden files loses the counter; only history/000001.json and undone/000002.json remain.
        try FileManager.default.removeItem(at: folder.url(for: .history).appending(path: ".next"))
        try folder.updateEdit(author: .system("Test"), reason: "Captions off again") { $0.look.rounded = true }
        #expect(try folder.history.latestSequence() == 3)
    }

    @Test func undoingIntoATakenNameKeepsBothSnapshots() throws {
        let folder = try ProjectFolderTests().makeProject()
        try folder.updateEdit(author: .system("Test"), reason: "Captions") { $0.look.rounded = false }
        let undone = folder.url(for: .history).appending(path: "undone")
        try FileManager.default.createDirectory(at: undone, withIntermediateDirectories: true)
        try Data("an older snapshot".utf8).write(to: undone.appending(path: "000001.json"))
        try folder.undo()
        let names = try FileManager.default.contentsOfDirectory(atPath: undone.path(percentEncoded: false)).sorted()
        #expect(names == ["000001-2.json", "000001.json"])
        #expect(try folder.history.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: ".pending-mutation.json").path))
    }

    @Test func aReplayedUndoSkipsASnapshotAlreadyArchived() throws {
        let folder = try ProjectFolderTests().makeProject()
        try folder.updateEdit(author: .system("Test"), reason: "Captions") { $0.look.rounded = false }
        let history = folder.url(for: .history)
        let undone = history.appending(path: "undone")
        try FileManager.default.createDirectory(at: undone, withIntermediateDirectories: true)
        // Interrupted after the copy landed but before the original was removed.
        try FileManager.default.copyItem(at: history.appending(path: "000001.json"), to: undone.appending(path: "000001.json"))
        var restored = Edit()
        restored.revision = 2
        try folder.write(ProjectMutation.history(edit: restored, action: .undo(through: 1), redo: [RedoStack.Entry(edit: try folder.loadEdit(), reason: "Undo", author: .system("Test"))]), to: folder.url.appending(path: ".pending-mutation.json"))
        let reopened = try ProjectFolder(opening: folder.url)
        #expect(try FileManager.default.contentsOfDirectory(atPath: undone.path(percentEncoded: false)) == ["000001.json"])
        #expect(try reopened.history.entries().isEmpty)
    }

    @Test func aChangeThatCantBeFinishedSaysSo() throws {
        let fixture = ProjectFolderTests()
        let folder = try fixture.makeProject()
        let source = try fixture.addSource(to: folder)
        _ = try folder.addTranscript(fixture.draft(["original"]), for: source)
        let other = fixture.draft(["other"]).assigningIDs(source: source, firstWordNumber: 9, firstSilenceNumber: 9)
        try folder.write(ProjectMutation.transcript(project: try folder.loadProject(), transcript: other.transcript),
                         to: folder.url.appending(path: ".pending-mutation.json"))
        #expect {
            try ProjectFolder(opening: folder.url)
        } throws: { error in
            guard case .unfinishedChange(let url, _) = error as? ProjectFolderError else { return false }
            return url == folder.url
        }
    }

    @Test func aProjectOpensWhereItCantBeWritten() throws {
        let folder = try ProjectFolderTests().makeProject()
        let fileManager = FileManager.default
        try fileManager.removeItem(at: folder.url.appending(path: ProjectFolder.lockFileName))
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path(percentEncoded: false))
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path(percentEncoded: false)) }
        let opened = try ProjectFolder(opening: folder.url)
        #expect(try opened.loadProject().title == "Editing with Claude")
    }

    @Test func newerTranscriptFormatsAreRefused() throws {
        let folder = try ProjectFolderTests().makeProject()
        var transcript = talkingHead
        transcript.formatVersion += 1
        try folder.write(transcript, to: folder.transcriptURL(for: transcript.source))
        #expect(throws: ProjectFolderError.newerFormat(folder.transcriptURL(for: transcript.source), transcript.formatVersion)) {
            try folder.loadTranscript(for: transcript.source)
        }
    }
    @Test func aFailedDiskWriteLeavesRecoverableIntent() throws {
        let folder = try ProjectFolderTests().makeProject()
        #expect(throws: (any Error).self) {
            try folder.updateEdit(author: .system("Test"), reason: "Captions") {
                $0.look.rounded = false
                // Force the final edit write to fail after its old value has been read.
                try FileManager.default.removeItem(at: folder.editFileURL)
                try FileManager.default.createDirectory(at: folder.editFileURL, withIntermediateDirectories: true)
                try Data([0]).write(to: folder.editFileURL.appending(path: "obstruction"))
            }
        }
        #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: ".pending-mutation.json").path))
        try FileManager.default.removeItem(at: folder.editFileURL)
        let reopened = try ProjectFolder(opening: folder.url)
        #expect(try reopened.loadEdit().look.rounded == false)
        #expect(try reopened.history.entries().count == 1)
        #expect(try reopened.undo().look.rounded == true)
    }

}

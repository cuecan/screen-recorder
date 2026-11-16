import Foundation
import Testing
@testable import ProjectKit

struct EditorLifecycleTests {
    @Test func fittedTimelineIncludesItsScrollMarginAndUsesTheSliderRange() {
        let zoom = TimelineZoom.fitted(duration: 10, viewport: 800)
        #expect(10 * zoom + TimelineZoom.horizontalPadding == 800)
        #expect(TimelineZoom.fitted(duration: 0.01, viewport: 1600) == TimelineZoom.range.upperBound)
        #expect(abs(3600 * TimelineZoom.fitted(duration: 3600, viewport: 500) + TimelineZoom.horizontalPadding - 500) < 0.001)
        #expect(TimelineZoom.fitted(duration: 0, viewport: 800) == TimelineZoom.range.lowerBound)
        #expect(TimelineZoom.fitted(duration: .nan, viewport: 800) == TimelineZoom.range.lowerBound)
        #expect(TimelineZoom.fitted(duration: 10, viewport: .infinity) == TimelineZoom.range.lowerBound)
    }

    @Test func selectionsHaveOneKindAndAnEdgeKeepsItsClip() {
        let id = ClipID(number: 1)
        let source = SourceID(number: 1)
        let selection = EditorSelection.clipEdge(clip: id, edge: .end)
        #expect(selection.clipIDs == [id])
        #expect(selection.overlayIDs.isEmpty)
        #expect(selection.persisted.clips == [id])
        let edit = Edit(main: [Clip(id: id, source: source, sourceIn: 0, sourceOut: 1)])
        #expect(selection.retaining(in: edit) == selection)
        #expect(selection.retaining(in: Edit()) == .none)
    }

    @Test func aStalePreviewReadOrBuildCannotWin() {
        var load = PreviewLoad()
        let old = load.begin()
        let current = load.begin()
        load.finish(old, outcome: .ready)
        #expect(load.contains(current))
        load.finish(old, outcome: .failed("Missing media"))
        #expect(load.contains(current))
        load.finish(current, outcome: .ready)
        #expect(load.state == .ready(current))
        let closing = load.begin()
        load.cancel()
        load.finish(closing, outcome: .ready)
        #expect(load.state == .idle)
    }

    @Test func replacingSoundKeepsThePendingPicturePosterButANewPictureInvalidatesIt() {
        var load = PreviewLoad()
        let picture = load.begin()
        load.installed(picture)
        load.finish(picture, outcome: .ready)
        // Normalized/raw sound uses another item with exactly the same pictures.
        load.installed(picture)
        #expect(load.state == .seeking(picture))
        #expect(load.acceptsPoster(for: picture))
        load.finish(picture, outcome: .ready)
        let newPicture = load.begin()
        load.installed(picture)
        #expect(load.state == .loading(newPicture))
        #expect(!load.acceptsPoster(for: picture))
    }

    @Test func postersCannotOutliveTheirInstalledPreview() {
        var load = PreviewLoad()
        let first = load.begin()
        #expect(!load.acceptsPoster(for: first))
        load.finish(first, outcome: .ready)
        #expect(load.acceptsPoster(for: first))
        let next = load.begin()
        #expect(!load.acceptsPoster(for: first))
        load.installed(next)
        #expect(load.isLoading, "A temporarily paused player during its initial seek has not reached the end.")
        #expect(load.acceptsPoster(for: next), "An installed item's fallback is independent of its seek.")
        load.finish(first, outcome: .ready)
        #expect(load.state == .seeking(next), "An old seek's completion cannot finish the replacement.")
        load.finish(next, outcome: .failed("Missing camera"))
        #expect(load.problem == "Missing camera")
        #expect(!load.acceptsPoster(for: next))
        let empty = load.begin()
        #expect(load.problem == nil)
        load.finish(empty, outcome: .empty)
        #expect(load.state == .empty)
        #expect(!load.acceptsPoster(for: empty))
        let closing = load.begin()
        load.finish(closing, outcome: .ready)
        load.cancel()
        #expect(!load.acceptsPoster(for: closing))
    }

    @Test func shuttlingStopsAndChangesDirectionWithoutRetainingOldSpeed() {
        var playback = EditorPlayback()
        playback.shuttle(.backward)
        playback.shuttle(.backward)
        #expect(playback.rate == -2)
        playback.shuttle(.forward)
        #expect(playback.rate == 1)
        for _ in 0..<5 { playback.shuttle(.forward) }
        #expect(playback.rate == 8)
        playback.pause()
        #expect(!playback.isPlaying)
        playback.shuttle(.forward)
        #expect(playback.rate == 1)
    }

    @Test func exportsKeepCompletedFilesAndIgnoreLateProgress() throws {
        var job = ExportJob()
        let firstID = job.start([.video(.landscape), .video(.vertical)])
        let first = try #require(firstID)
        let duplicate = job.start([.handoff])
        #expect(duplicate == nil)
        let file = URL(filePath: "/tmp/finished.mp4")
        job.complete(.video(.landscape), files: [file], attempt: first)
        job.update(.video(.landscape), progress: 0.5, attempt: first)
        #expect(job.rows[0].state == .complete([file]))
        job.stop()
        job.finish(.cancelled, attempt: first)
        #expect(job.rows[0].files == [file])
        #expect(job.phase == .finished(.cancelled))
        job.reset()
        let retryID = job.start([.video(.landscape)])
        let retry = try #require(retryID)
        job.update(.video(.landscape), progress: 1, attempt: first)
        job.finish(.success, attempt: first)
        #expect(job.phase == .running)
        #expect(job.rows[0].state == .waiting)
        job.finish(.failed("Disk full"), attempt: retry)
        #expect(job.phase.title == "Export failed")
    }

    @Test func aFailedHistoryWriteRecoversTheRedoStackWithTheEdit() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "Recovery")
        try folder.updateEdit(author: .app, reason: "Gutter") { $0.look.background = "#FFFFFF" }
        try folder.undo()
        #expect(folder.canRedo)
        let redoURL = folder.url(for: .history).appending(path: "redo.json")
        // Make committing the new redo stack fail after the edit was written.
        try FileManager.default.removeItem(at: redoURL)
        try FileManager.default.createDirectory(at: redoURL, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) {
            try folder.updateEdit(author: .app, reason: "New branch") { $0.look.background = "#D9D9D9" }
        }
        let pending = folder.url.appending(path: ".pending-mutation.json")
        #expect(FileManager.default.fileExists(atPath: pending.path))
        try FileManager.default.removeItem(at: redoURL)
        let recovered = try ProjectFolder(opening: folder.url)
        #expect(try recovered.loadEdit().look.background == "#D9D9D9")
        #expect(!recovered.canRedo)
        #expect(!FileManager.default.fileExists(atPath: pending.path))
    }

    @Test func interruptedUndoReplaysWithoutDuplicatingRedo() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "Undo recovery")
        let edited = try folder.updateEdit(author: .app, reason: "Gutter") { $0.look.background = "#FFFFFF" }
        let snapshot = try #require(folder.history.entries().first)
        var restored = snapshot.edit
        restored.revision = edited.revision + 1
        let redo = [RedoStack.Entry(edit: edited, reason: "Gutter", author: .app)]
        let pending = ProjectMutation.history(edit: restored, action: .undo(through: snapshot.sequence), redo: redo)
        let pendingURL = folder.url.appending(path: ".pending-mutation.json")
        for _ in 0..<2 {
            try folder.write(pending, to: pendingURL)
            _ = try ProjectFolder(opening: folder.url)
            #expect(try folder.redoStack.entries().count == 1)
        }
        #expect(try folder.redo(author: .app).look.background == "#FFFFFF")
        #expect(!folder.canRedo)
    }

    @Test func corruptRedoNeitherBlocksUndoNorIsLost() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "Corrupt redo")
        try folder.updateEdit(author: .app, reason: "Gutter") { $0.look.background = "#FFFFFF" }
        let history = folder.url(for: .history)
        try Data("broken".utf8).write(to: history.appending(path: "redo.json"))
        #expect(!folder.canRedo)
        // Undo still works…
        #expect(try folder.undo().look.background == "#000000")
        // …the damaged file is kept beside the history, not overwritten…
        let aside = try FileManager.default.contentsOfDirectory(atPath: history.path(percentEncoded: false)).filter { $0.hasPrefix("redo-unreadable-") }
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: history.appending(path: aside[0])) == Data("broken".utf8))
        // …and what this undo replaced can be redone.
        #expect(try folder.redo(author: .app).look.background == "#FFFFFF")
    }
}

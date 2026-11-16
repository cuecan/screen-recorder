import Foundation
import ProjectKit
import Testing
@testable import CueCan

/// Exercises the actual editor actions and persisted edit: a marked range must never accidentally
/// delete the whole clip that was selected before I/O.
@MainActor
struct EditorRangeTests {
    @Test func markingARangeReplacesTheClipSelectionAndDeleteCutsOnlyThatRange() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(selecting: ClipID(number: 1))
        model.seek(to: 2)
        model.mark(in: true)
        model.seek(to: 5)
        model.mark(in: false)
        #expect(model.selection.isEmpty)
        model.deleteSelection()
        let edit = try folder.loadEdit()
        #expect(abs(edit.duration - 7) < 0.001)
        #expect(edit.main.map(\.playedRange) == [TimeRange(start: 0, end: 2), TimeRange(start: 5, end: 10)])
        #expect(model.markedRange == nil)
    }

    @Test func pickingAClipDoesNotApplyOldRangeMarksToAHold() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        model.markIn = 2
        model.markOut = 5
        model.selection = .clips([ClipID(number: 1)])
        #expect(model.selectedRange == nil)
        model.freezeSelection()
        let hold = try #require(folder.loadEdit().freezes.first)
        #expect(hold.range == TimeRange(start: 0, end: 10))
    }

    private func makeFolder() throws -> ProjectFolder {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-editor-range-\(UUID().uuidString)")
        let folder = try ProjectFolder.create(at: url, title: "Range interaction regression")
        let project = try folder.updateProject { project in
            project.addSource(name: "QA camera", origin: .recorded, tracks: [
                SourceTrack(kind: .camera, file: .inProject("recordings/fixture.mov"), startOffset: 0,
                            media: MediaInfo(duration: 10, video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1")))
            ])
        }
        if let source = project.sources.first {
            try folder.updateEdit(author: .app, reason: "Fixture") { $0.addWholeSource(source) }
        }
        return folder
    }
}

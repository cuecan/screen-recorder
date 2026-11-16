import Foundation
import Testing
@testable import ProjectKit

/// Duplicating a project (docs/decisions.md, 77): its own edit over the same recordings.
@Suite struct DuplicatingTests {
    let root: URL
    let library: ProjectLibrary

    init() throws {
        root = URL.temporaryDirectory.appending(path: "cuecan-duplicating-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = ProjectLibrary(projectsFolder: root, recentsFile: root.appending(path: "recent.json"))
    }

    func take() throws -> ProjectFolder {
        let folder = try ProjectFolder.create(at: root.appending(path: "Take"), title: "Take")
        try Data("screen".utf8).write(to: folder.url(for: .recordings).appending(path: "screen.mov"))
        try Data("export".utf8).write(to: folder.url(for: .exports).appending(path: "Take.mp4"))
        try folder.updateProject { project in
            project.format = VideoFormat(destination: .both)
            project.addSource(name: "Take", origin: .recorded, tracks: [
                SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"),
                            media: MediaInfo(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
            ])
        }
        try folder.updateEdit(author: .app, reason: "Clips") { edit in
            edit.main = [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 6),
                         Clip(id: ClipID(number: 2), source: SourceID(number: 1), sourceIn: 6, sourceOut: 10)]
        }
        try folder.saveEditorState(EditorState(playhead: 2, shape: .vertical))
        return folder
    }

    @Test func aCopyIsAProjectOfItsOwnOverTheSameRecordings() throws {
        let original = try take()
        let copy = try library.duplicate(original)
        #expect(copy.url.lastPathComponent == "Take copy")
        let project = try copy.loadProject(), source = try original.loadProject()
        #expect(project.id != source.id && project.copyOf == source.id)
        #expect(project.title == "Take copy" && project.createdAt == source.createdAt)
        #expect(project.sources == source.sources && project.format == source.format)
        #expect(source.copyOf == nil)
        #expect(try copy.loadEdit() == original.loadEdit())
        #expect(try Data(contentsOf: copy.url(for: .recordings).appending(path: "screen.mov")) == Data("screen".utf8))
        #expect(try copy.loadEditorState()?.shape == .vertical, "The shape it shows comes along.")
        #expect(try copy.history.entries().count == original.history.entries().count)
    }

    @Test func shorteningAClipInOneLeavesTheOther() throws {
        let original = try take()
        let copy = try library.duplicate(original)
        try copy.updateEdit(author: .app, reason: "Tighten") { $0.main[0].sourceOut = 3 }
        #expect(try copy.loadEdit().main[0].sourceOut == 3)
        #expect(try original.loadEdit().main[0].sourceOut == 6)
        try original.updateEdit(author: .app, reason: "Remove") { $0.main.removeLast() }
        #expect(try copy.loadEdit().main.count == 2)
    }

    @Test func theOriginalCanGoWithoutTheCopy() throws {
        let original = try take()
        let copy = try library.duplicate(original)
        try FileManager.default.removeItem(at: original.url)
        #expect(try ProjectFolder(opening: copy.url).loadEdit().main.count == 2)
        #expect(FileManager.default.fileExists(atPath: copy.url(for: .recordings).appending(path: "screen.mov").path(percentEncoded: false)))
    }

    @Test func aCopyStartsWithoutTheOriginalsExportsOrLock() throws {
        let original = try take()
        let copy = try library.duplicate(original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: copy.url(for: .exports).path(percentEncoded: false)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: copy.url.appending(path: ProjectFolder.lockFileName).path(percentEncoded: false))
            || (try? copy.withLock { true }) == true)
    }

    @Test func copiesAreNumberedAndNamedAfterTheOriginal() throws {
        let original = try take()
        let first = try library.duplicate(original)
        let second = try library.duplicate(original)
        let ofACopy = try library.duplicate(first)
        #expect([first, second, ofACopy].map(\.url.lastPathComponent) == ["Take copy", "Take copy 2", "Take copy 3"])
        #expect(try ofACopy.loadProject().title == "Take copy 3")
        #expect(try ofACopy.loadProject().copyOf == first.loadProject().id)
        #expect(library.projects().count == 4)
    }

    @Test func aTakenDestinationIsRefused() throws {
        let original = try take()
        #expect(throws: ProjectFolderError.alreadyAProject(original.url)) { try original.duplicate(to: original.url, title: "Again") }
    }

    @Test func theEditorsShapeRoundTrips() throws {
        let state = EditorState(playhead: 1, shape: .vertical)
        #expect(try JSONDecoder().decode(EditorState.self, from: JSONEncoder().encode(state)).shape == .vertical)
        #expect(try JSONDecoder().decode(EditorState.self, from: JSONEncoder().encode(EditorState())).shape == nil)
    }
}

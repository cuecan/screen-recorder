import Foundation
import Testing
@testable import RenderKit

struct ExportPublicationTests {
    @Test func aLateCollisionPreservesTheEarlierExportAndRollsBackTheGroup() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cuecan-publication-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appending(path: "staging")
        let destination = root.appending(path: "chosen-folder")
        for folder in [staging, destination] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let srt = staging.appending(path: "Export.srt")
        let text = staging.appending(path: "Export.txt")
        try Data("New captions".utf8).write(to: srt)
        try Data("New text".utf8).write(to: text)
        let previous = destination.appending(path: "Export.txt")
        try Data("Keep this earlier export".utf8).write(to: previous)
        #expect(throws: (any Error).self) { try ExportPublication.publish([srt, text], to: destination) }
        #expect(try String(contentsOf: previous, encoding: .utf8) == "Keep this earlier export")
        #expect(FileManager.default.fileExists(atPath: srt.path))
        #expect(FileManager.default.fileExists(atPath: text.path))
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "Export.srt").path))
    }

    @Test func successfulPublicationReturnsOnlyFinalFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cuecan-publication-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let staging = root.appending(path: "staging")
        let destination = root.appending(path: "chosen-folder")
        for folder in [staging, destination] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let video = staging.appending(path: "Export.mp4")
        try Data("QA bytes, not media".utf8).write(to: video)
        let files = try ExportPublication.publish([video], to: destination)
        #expect(files.map(\.lastPathComponent) == ["Export.mp4"])
        #expect(!FileManager.default.fileExists(atPath: video.path))
        #expect(try Data(contentsOf: #require(files.first)) == Data("QA bytes, not media".utf8))
    }
}

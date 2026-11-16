import Foundation
import ProjectKit
import Testing
@testable import RenderKit

struct TrimPreviewSessionTests {
    @Test func theLoupeReadsBothSidesAndTheFinalPartialFrameThroughTheCompositor() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cuecan-trim-frames-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ProjectFolder.create(at: root, title: "Trim frame plumbing")
        for (name, color) in [("red", SyntheticMedia.red), ("blue", SyntheticMedia.blue)] {
            try await SyntheticMedia.writeVideo(color, width: 64, height: 64, seconds: 0.3,
                                                to: folder.url(for: .recordings).appending(path: "\(name).mov"))
            try folder.updateProject { project in
                project.addSource(name: name, origin: .recorded, tracks: [
                    SourceTrack(kind: .camera, file: .inProject("recordings/\(name).mov"),
                                media: MediaInfo(duration: 0.3, video: .init(width: 64, height: 64, frameRate: 30, captureRate: 30, codec: "avc1")))
                ])
            }
        }
        let first = Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 0.2, layout: .camera)
        let second = Clip(id: ClipID(number: 2), source: SourceID(number: 2), sourceIn: 0, sourceOut: 0.2, layout: .camera)
        try folder.updateEdit(author: .system("Test"), reason: "Two colors") { $0.main = [first, second] }
        let edit = try folder.loadEdit()
        let plan = try TrimPreviewPlan(edit: edit, clip: first.id, edge: .end, sourceTime: 0.115,
                                       sourceDuration: 0.3, frameDuration: 1.0 / 30)
        let reader = try TrimPreviewSession(folder: folder)
        let pair = try await reader.frames(for: plan)
        let outgoing = try #require(pair.outgoing)
        let incoming = try #require(pair.incoming)
        #expect(abs(outgoing.time - 0.1) < 1e-9)
        #expect(abs(incoming.time - 4.0 / 30) < 1e-9)
        #expect(try #require(SyntheticMedia.pixel(outgoing.jpeg, x: outgoing.width / 2, y: outgoing.height / 2)).isClose(to: SyntheticMedia.red))
        #expect(try #require(SyntheticMedia.pixel(incoming.jpeg, x: incoming.width / 2, y: incoming.height / 2)).isClose(to: SyntheticMedia.blue))
        let terminal = try TrimPreviewPlan(edit: Edit(main: [first]), clip: first.id, edge: .end, sourceTime: 0.115,
                                           sourceDuration: 0.3, frameDuration: 1.0 / 30)
        let last = try await reader.frames(for: terminal)
        #expect(last.incoming == nil)
        #expect(abs(try #require(last.outgoing).time - 0.1) < 1e-9)
        #expect(try folder.loadEdit() == edit)
        try folder.updateProject { $0.sources[0].tracks[0].startOffset = 0.05 }
        let opening = try TrimPreviewPlan(edit: Edit(main: [first]), clip: first.id, edge: .start, sourceTime: 0,
                                          sourceDuration: 0.35, frameDuration: 1.0 / 30)
        let lateReader = try TrimPreviewSession(folder: folder)
        let openingFrames = try await lateReader.frames(for: opening)
        #expect(openingFrames.outgoing == nil)
        // A screen that starts late holds its first frame from zero, so the take's first frame is at zero.
        #expect(try #require(openingFrames.incoming).time == 0)
    }
}

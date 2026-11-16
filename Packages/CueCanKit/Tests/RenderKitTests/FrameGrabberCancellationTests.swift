import AVFoundation
import Foundation
import ProjectKit
import Testing
@testable import RenderKit

struct FrameGrabberCancellationTests {
    @Test func cancellingConcurrentPosterReadsLeavesFreshReadersUsable() async throws {
        let (folder, inputs) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let iterations = Int(ProcessInfo.processInfo.environment["CUECAN_POSTER_CANCEL_ITERATIONS"] ?? "12") ?? 12
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    for index in 0..<iterations {
                        let built = try await CompositionBuilder.build(inputs, output: .landscape, scale: 0.25)
                        let read = Task { try await FrameGrabber.stills(of: built, at: Array(repeating: 0.5, count: 20)) }
                        try await Task.sleep(for: .microseconds([0, 100, 500, 2_000][index % 4]))
                        read.cancel()
                        do {
                            _ = try await read.value
                            Issue.record("A cancelled multi-frame read must report cancellation.")
                        } catch is CancellationError { }
                        try await checkFreshFrame(inputs)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func cancellingDuringLongerReadsKeepsTheDecoderUsable() async throws {
        let (folder, inputs) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let iterations = Int(ProcessInfo.processInfo.environment["CUECAN_POSTER_LATE_CANCEL_ITERATIONS"] ?? "12") ?? 12
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    for index in 0..<iterations {
                        let built = try await CompositionBuilder.build(inputs, output: .landscape, scale: 0.25)
                        let read = Task { try await FrameGrabber.stills(of: built, at: Array(repeating: 0.5, count: 500)) }
                        try await Task.sleep(for: .milliseconds([10, 20, 50, 100][index % 4]))
                        read.cancel()
                        await #expect(throws: CancellationError.self) { try await read.value }
                        try await checkFreshFrame(inputs)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    private func checkFreshFrame(_ inputs: RenderInputs) async throws {
        let fresh = try await CompositionBuilder.build(inputs, output: .landscape, scale: 0.25)
        let still = try #require(try await FrameGrabber.stills(of: fresh, at: [0.5], maximumWidth: 480).first)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 240, y: 135)?.isClose(to: SyntheticMedia.red) == true)
    }

    private func fixture() async throws -> (ProjectFolder, RenderInputs) {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-poster-cancellation-\(UUID())")
        let folder = try ProjectFolder.create(at: url, title: "Poster cancellation")
        var madeFixture = false
        defer { if !madeFixture { try? FileManager.default.removeItem(at: folder.url) } }
        try await SyntheticMedia.writeVideo(SyntheticMedia.red, width: 640, height: 360, seconds: 2,
                                            to: folder.url(for: .recordings).appending(path: "screen.mov"))
        try folder.updateProject { project in
            project.addSource(name: "Screen", origin: .recorded, tracks: [
                SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"),
                            media: MediaInfo(duration: 2, video: .init(width: 640, height: 360, frameRate: 30, captureRate: 30, codec: "avc1"))),
            ], captureArea: CaptureArea(ratio: .sixteenByNine, heightPoints: 360))
        }
        try folder.updateEdit(author: .app, reason: "Use screen") { edit in
            edit.main = [.init(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 2, layout: .screen)]
            edit.look.inset = .none
        }
        let inputs = try RenderInputs.load(folder)
        madeFixture = true
        return (folder, inputs)
    }
}

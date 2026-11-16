import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ProjectKit
import RecorderKit
import RenderKit
import Testing
@testable import CueCan

@MainActor
struct MixUpdateTests {
    @Test func anInPlaceMixUpdateRefreshesTimelineLevelsWithoutReplacingTheItem() async throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-mix-review-\(UUID())"), title: "Mix update fixture")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let url = folder.url(for: .recordings).appending(path: "mic.wav")
        let writer = try WAVStreamWriter(url: url, sampleRate: 48_000)
        try writer.append([Float](repeating: 0.1, count: 48_000))
        try writer.finish()
        let project = try folder.updateProject { project in
            project.addSource(name: "Fixture mic", origin: .recorded, tracks: [
                SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"),
                            media: MediaInfo(duration: 1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
            ])
        }
        let source = try #require(project.sources.first)
        let picture = folder.url.appending(path: "fixture.png")
        let context = try #require(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(picture as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        try folder.updateEdit(author: .app, reason: "Fixture") { edit in
            edit.addWholeSource(source)
            try edit.placeOverlay(.file(at: picture), overTimeline: TimeRange(start: 0, end: 1))
        }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        let before = try await CompositionBuilder.build(RenderInputs.load(folder), output: .landscape)
        let item = before.makePlayerItem()
        model.player.replaceCurrentItem(with: item)
        let id = try #require(model.edit?.main.first?.id)
        try folder.updateEdit(author: .app, reason: "Level") { try $0.setSound(.init(voiceLevel: -18), for: [id]) }
        let snapshot = try EditorSnapshot.load(folder)
        let inputs = snapshot.inputs
        let updated = try await CompositionBuilder.build(inputs, output: .landscape)
        model.installMix(updated, snapshot: snapshot, dates: [], on: item)
        #expect(model.player.currentItem === item)
        #expect(model.edit?.main.first?.voiceLevel == -18)
        #expect(model.timeline?.clips.first?.clip.voiceLevel == -18, "The drawn and draggable line must use the level that is playing.")
        #expect(model.timeline?.clips.map(\.clip) == inputs.edit.main)
        #expect(model.edit?.revision == inputs.edit.revision)
        model.player.replaceCurrentItem(with: nil)
    }
}

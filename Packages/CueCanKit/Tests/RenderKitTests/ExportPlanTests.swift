import AVFoundation
import Foundation
import Testing
import ProjectKit
@testable import RenderKit

struct ExportPlanTests {
    @Test func reviewedNamesAndCollisionsSurviveTheHelperSnapshot() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-named-export-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Original take")
        let destination = url.appending(path: "chosen-folder")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let plan = ExportPlan(inputs: try RenderInputs.load(folder), destination: destination,
                              kind: .finished(outputs: [.landscape, .vertical], transcript: true, settings: .init()),
                              name: "Launch / final")
        let decoded = try JSONDecoder().decode(ExportPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded.inputs.project.title == "Original take")
        #expect(decoded.outputURLs.map(\.lastPathComponent) == ["Launch - final.mp4", "Launch - final Short.mp4", "Launch - final.srt", "Launch - final.txt"])
        #expect(decoded.outputURLs.allSatisfy { $0.deletingLastPathComponent().pathComponents == destination.pathComponents })
        #expect(decoded.existingOutputs().isEmpty)
        let existing = decoded.fileURL(extension: "srt")
        try Data("Earlier export".utf8).write(to: existing)
        #expect(decoded.existingOutputs() == [existing])
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Earlier export")
    }

    @Test func bothCompositionsUseTheCapturedAudioAfterTheSidecarChanges() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-export-plan-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "  A/B  ")
        let raw = folder.url(for: .recordings).appending(path: "raw.wav")
        let old = folder.url(for: .audio).appending(path: "old.wav")
        let new = folder.url(for: .audio).appending(path: "new.wav")
        for file in [raw, old, new] { try SyntheticMedia.writeTone(seconds: 0.2, to: file) }
        let track = SourceTrack(kind: .microphone, file: .inProject("recordings/raw.wav"),
                                media: MediaInfo(duration: 0.2, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
        try await SyntheticMedia.writeVideo(SyntheticMedia.blue, width: 64, height: 64, seconds: 0.2,
                                            to: folder.url(for: .recordings).appending(path: "camera.mov"))
        let camera = SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"),
                                 media: MediaInfo(duration: 0.2, video: .init(width: 64, height: 64, frameRate: 30, captureRate: 30, codec: "avc1")))
        try folder.updateProject { $0.addSource(name: "Camera", origin: .recorded, tracks: [camera, track]) }
        let source = SourceID(number: 1)
        try folder.updateEdit(author: .system("Test"), reason: "Whole mic") { $0.main = [clip(1, 0, 0.2)] }
        let settings = try folder.loadEdit().audio.settings(for: source)
        try folder.saveCleanedAudio(.init(source: source, settings: settings, file: "old.wav", original: track.file))
        let plan = ExportPlan(inputs: try RenderInputs.load(folder), destination: folder.url(for: .exports),
                              kind: .finished(outputs: [.landscape, .vertical], transcript: true, settings: .init()))
        let landscape = try await CompositionBuilder.build(plan.inputs, output: .landscape)
        var changed = settings
        changed.voice.amount = settings.voice.amount == 20 ? 30 : 20
        try folder.updateEdit(author: .system("Test"), reason: "New settings") { $0.audio.set(changed, for: source) }
        try folder.saveCleanedAudio(.init(source: source, settings: changed, file: "new.wav", original: track.file))
        let encoded = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(ExportPlan.self, from: encoded)
        let vertical = try await CompositionBuilder.build(decoded.inputs, output: .vertical)
        for composition in [landscape, vertical] {
            let urls = composition.composition.tracks(withMediaType: .audio).flatMap(\.segments).compactMap(\.sourceURL)
            #expect(urls == [old])
        }
        #expect(decoded.inputs.edit.audio.settings(for: source) == settings)
        #expect(decoded.baseName == "A-B")
        #expect(decoded.videoURL(.vertical).lastPathComponent == "A-B Short.mp4")
        #expect(try RenderInputs.load(folder).primaryAudio[source] == new)
    }
}

import Foundation
import ProjectKit
import Testing
@testable import RenderKit

struct ExportAudioSnapshotTests {
    @Test func repeatedCleanupCannotRemoveAQueuedExportsCapturedAudio() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cuecan-export-audio-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ProjectFolder.create(at: root, title: "Audio retention regression")
        let track = SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"),
                                media: MediaInfo(duration: 1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
        let project = try folder.updateProject { $0.addSource(name: "Mic", origin: .recorded, tracks: [track]) }
        let source = try #require(project.sources.first?.id)
        let settings = try folder.loadEdit().audio.settings(for: source)
        let original = folder.url(for: .audio).appending(path: "\(source)-first.wav")
        try Data("First cleanup bytes".utf8).write(to: original)
        try folder.saveCleanedAudio(.init(source: source, settings: settings, file: original.lastPathComponent, original: track.file))
        let inputs = try RenderInputs.load(folder)
        let snapshot = try ExportAudioSnapshot.capture(inputs)
        let retained = try #require(snapshot.inputs.primaryAudio[source])
        #expect(retained != original)
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: original.path)
        let retainedAttributes = try FileManager.default.attributesOfItem(atPath: retained.path)
        let originalFileNumber = try #require(originalAttributes[.systemFileNumber] as? NSNumber)
        let retainedFileNumber = try #require(retainedAttributes[.systemFileNumber] as? NSNumber)
        #expect(originalFileNumber == retainedFileNumber)

        // The existing cleanup policy retains one preceding version. A second replacement removes it.
        for version in ["second", "third"] {
            let file = folder.url(for: .audio).appending(path: "\(source)-\(version).wav")
            try Data(version.utf8).write(to: file)
            try folder.saveCleanedAudio(.init(source: source, settings: settings, file: file.lastPathComponent, original: track.file))
        }
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(try String(contentsOf: retained, encoding: .utf8) == "First cleanup bytes")
        let plan = ExportPlan(inputs: snapshot.inputs, destination: root.appending(path: "out"),
                              kind: .finished(outputs: [], transcript: true, settings: .init()))
        let decoded = try JSONDecoder().decode(ExportPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded.inputs.primaryAudio[source] == retained)
        try snapshot.release()
        #expect(!FileManager.default.fileExists(atPath: retained.deletingLastPathComponent().path))
        #expect(folder.cleanedAudioURL(for: source, settings: settings, original: track.file) != nil)
    }

    @Test func rawRecordingsDoNotNeedExtraFilesAndFailedCaptureLeavesNoDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cuecan-export-audio-failure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ProjectFolder.create(at: root, title: "Audio capture failure regression")
        let track = SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"),
                                media: MediaInfo(duration: 1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
        let project = try folder.updateProject { $0.addSource(name: "Mic", origin: .recorded, tracks: [track]) }
        let source = try #require(project.sources.first?.id)
        let raw = try RenderInputs.load(folder)
        let snapshot = try ExportAudioSnapshot.capture(raw)
        #expect(snapshot.inputs.primaryAudio == raw.primaryAudio)
        try snapshot.release()
        let settings = try folder.loadEdit().audio.settings(for: source)
        let cleaned = folder.url(for: .audio).appending(path: "\(source)-missing.wav")
        try Data("Cleaned bytes".utf8).write(to: cleaned)
        try folder.saveCleanedAudio(.init(source: source, settings: settings, file: cleaned.lastPathComponent, original: track.file))
        let inputs = try RenderInputs.load(folder)
        try FileManager.default.removeItem(at: cleaned)
        #expect(throws: (any Error).self) { try ExportAudioSnapshot.capture(inputs) }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.url.path)
        #expect(!names.contains { $0.hasPrefix(".export-inputs-") })
    }
}

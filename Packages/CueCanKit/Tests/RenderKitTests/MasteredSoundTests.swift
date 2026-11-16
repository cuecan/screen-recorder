import AVFoundation
import AudioKit
import Foundation
import ProjectKit
import Testing
@testable import RenderKit

struct MasteredSoundTests {
    @Test func visualEditsReuseTheSoundKeyWhileMixAndTimingChangesInvalidateIt() async throws {
        let folder = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let inputs = try RenderInputs.load(folder)
        let original = try await CompositionBuilder.build(inputs, output: .landscape, scale: 0.1)
        let key = try PreviewSoundKey.make(for: original, target: -14, ceiling: -1)
        let visual = inputs.withEdit {
            $0.revision += 1
            $0.main[0].layout = .automatic
            $0.look.background = "#FFFFFF"
        }
        let differentPictures = try await CompositionBuilder.build(visual, outputs: [.landscape, .vertical], scale: 0.2)
        #expect(try PreviewSoundKey.make(for: differentPictures, target: -14, ceiling: -1) == key)
        #expect(try PreviewSoundKey.make(for: original, target: -16, ceiling: -1) != key)
        #expect(try PreviewSoundKey.make(for: original, target: -14, ceiling: -2) != key)
        for changed in [inputs.withEdit { $0.main[0].voiceLevel -= 1 },
                        inputs.withEdit { $0.main[0].systemAudioLevel -= 1 },
                        inputs.withEdit { $0.main[0].sourceOut -= 0.1 },
                        inputs.withEdit { $0.main[0].isMuted = true },
                        inputs.withEdit { $0.main[1].startsAtSplit = true }] {
            let built = try await CompositionBuilder.build(changed, output: .landscape, scale: 0.1)
            #expect(try PreviewSoundKey.make(for: built, target: -14, ceiling: -1) != key)
        }
    }

    @Test func anAudioOnlyPosterReturnsAnErrorInsteadOfRaisingAnObjectiveCException() async throws {
        let folder = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.updateProject { $0.sources[0].tracks.removeAll { $0.kind == .camera } }
        let image = folder.url.appending(path: "overlay.png")
        try SyntheticMedia.writePNG(SyntheticMedia.blue, width: 16, height: 16, to: image)
        try folder.updateEdit(author: .app, reason: "Still over audio") {
            try $0.placeOverlay(.file(at: image), overTimeline: TimeRange(start: 0, end: 1.2))
        }
        let built = try await CompositionBuilder.build(RenderInputs.load(folder), output: .landscape, scale: 0.1)
        await #expect(throws: RenderError.self) { try await FrameGrabber.stills(of: built, at: [0.2]) }
    }

    @Test(arguments: [false, true])
    func previewUsesTheExportMixOnceAndKeepsItsTiming(withBothOutputs: Bool) async throws {
        let folder = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let inputs = try RenderInputs.load(folder)
        let built = try await CompositionBuilder.build(inputs, outputs: withBothOutputs ? [.landscape, .vertical] : [.landscape], scale: 0.1)
        let mix = try await AudioMixRenderer.render(built)
        let expected = LoudnessStage.process(AudioSamples(samples: mix, sampleRate: 48_000))
        let file = folder.url.appending(path: "mastered.wav")
        #expect(try await MasteredSound.writeMix(of: built, to: file) { samples, rate in
            try LoudnessStage.process(AudioSamples(samples: samples, sampleRate: rate), checkpoint: { try Task.checkCancellation() }).audio.samples
        })
        let written = try await AudioFileReader.readMono(file)
        #expect(written.samples == expected.audio.samples)
        let originalTracks = built.audioTrackIDs
        let normalized = try await MasteredSound.replacingSound(in: built, with: file)
        #expect(built.audioTrackIDs == originalTracks && built.composition.tracks(withMediaType: .audio).count == originalTracks.count)
        #expect(normalized.audioTrackIDs.count == 1)
        #expect(normalized.timeline.duration == built.timeline.duration)
        let audible = try await AudioMixRenderer.render(normalized)
        #expect(audible.count == expected.audio.samples.count)
        let error = zip(audible, expected.audio.samples).map { abs($0 - $1) }.max() ?? 0
        #expect(error < 0.000_001, "The mastered mix must not receive the clip gains a second time.")
        #expect(abs(LoudnessMeter.integratedLoudness(of: written) + 14) <= 0.1)
        #expect(TruePeakMeter.truePeak(of: written) <= -0.99)
    }

    @Test func cachedAudioSurvivesCacheClearUntilItsPlayerOwnerReleasesIt() async throws {
        let folder = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let built = try await CompositionBuilder.build(RenderInputs.load(folder), output: .landscape, scale: 0.1)
        let renderer = LoudnessPreviewRenderer()
        var first = try await renderer.audio(for: Data("same".utf8), of: built) { samples, _ in samples }
        let url = try #require(first?.url)
        var second = try await renderer.audio(for: Data("same".utf8), of: built) { _, _ in throw NSError(domain: "CacheMiss", code: 1) }
        #expect(second?.url == url)
        await renderer.clear()
        first = nil
        #expect(FileManager.default.fileExists(atPath: url.path))
        second = nil
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aSupersedingMixWaitsForTheCancelledWorkerAndCannotPublishItsFile() async throws {
        let folder = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let built = try await CompositionBuilder.build(RenderInputs.load(folder), output: .landscape, scale: 0.1)
        let other = try built.copyForReading()
        let renderer = LoudnessPreviewRenderer()
        let gate = MasteringGate()
        let old = Task {
            try await renderer.audio(for: Data("old".utf8), of: built) { samples, _ in
                await withTaskCancellationHandler { await gate.wait("old", samples: samples) } onCancel: { Task { await gate.cancelled() } }
            }
        }
        try await wait { await gate.started == ["old"] }
        let new = Task {
            try await renderer.audio(for: Data("new".utf8), of: other) { samples, _ in await gate.wait("new", samples: samples) }
        }
        try await wait { await gate.wasCancelled }
        #expect(await gate.started == ["old"])
        await gate.release()
        try await wait { await gate.started == ["old", "new"] }
        await gate.release()
        let oldResult = await old.result
        if case .success = oldResult { Issue.record("The superseded mix must be cancelled.") }
        #expect(try await new.value != nil)
        #expect(await gate.maximumActive == 1)
        await renderer.clear()
    }

    private func fixture() async throws -> ProjectFolder {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-mastered-sound-\(UUID())"), title: "Synthetic sound plumbing")
        let recordings = folder.url(for: .recordings)
        try await SyntheticMedia.writeVideo(SyntheticMedia.blue, width: 64, height: 64, seconds: 1.2, to: recordings.appending(path: "camera.mov"))
        try SyntheticMedia.writeTone(seconds: 1.2, amplitude: 0.06, to: recordings.appending(path: "voice.wav"))
        try SyntheticMedia.writeTone(seconds: 1.2, frequency: 440, amplitude: 0.02, to: recordings.appending(path: "system.wav"))
        let project = try folder.updateProject {
            $0.addSource(name: "Synthetic tones", origin: .recorded, tracks: [
                SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), media: MediaInfo(duration: 1.2, video: .init(width: 64, height: 64, frameRate: 30, captureRate: 30, codec: "avc1"))),
                SourceTrack(kind: .microphone, file: .inProject("recordings/voice.wav"), media: MediaInfo(duration: 1.2, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
                SourceTrack(kind: .systemAudio, file: .inProject("recordings/system.wav"), media: MediaInfo(duration: 1.2, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
            ])
        }
        let source = try #require(project.sources.first)
        try folder.updateEdit(author: .system("Test"), reason: "Two clip balances") { edit in
            edit.main = [Clip(id: ClipID(number: 1), source: source.id, sourceIn: 0, sourceOut: 0.6, layout: .camera),
                         Clip(id: ClipID(number: 2), source: source.id, sourceIn: 0.6, sourceOut: 1.2, layout: .camera)]
            edit.nextClipNumber = 3
            edit.main[0].systemAudioLevel = -6
            edit.main[1].voiceLevel = -12
            edit.main[1].systemAudioLevel = -20
        }
        return folder
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock().now + .seconds(5)
        while !(await condition()) {
            guard clock.now < deadline else { throw NSError(domain: "MasteringWait", code: 1) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor MasteringGate {
    private(set) var started: [String] = []
    private(set) var wasCancelled = false
    private(set) var maximumActive = 0
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait(_ label: String, samples: [Float]) async -> [Float] {
        started.append(label)
        active += 1
        maximumActive = max(maximumActive, active)
        await withCheckedContinuation { waiting.append($0) }
        active -= 1
        return samples
    }
    func cancelled() { wasCancelled = true }
    func release() { waiting.removeFirst().resume() }
}

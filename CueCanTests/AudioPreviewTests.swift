import AppKit
import AVFoundation
import Foundation
import ProjectKit
import RecorderKit
import Testing
@testable import CueCan

@MainActor
struct AudioPreviewTests {
    @Test func framingAcrossAPendingPreviewResizeSavesOnceAndUndoesCorrectly() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        defer { model.cancelTransformPreview(); model.player.replaceCurrentItem(with: nil) }
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        let before = try #require(model.edit)
        let id = try #require(before.main.first?.id)
        let historyCount = try fixture.folder.history.entries().count
        let initialItem = try #require(model.player.currentItem)
        model.selection = .clips([id])
        model.previewHeightChanged(toPixels: 1800)
        for index in 0..<16 {
            model.previewTransform(picture: .camera, centerX: Double(index) / 15, zoom: 1.8)
            try await Task.sleep(for: .milliseconds(50))
        }
        model.setTransform(picture: .camera, centerX: 0.25, centerY: 0.75, zoom: 1.8)
        let saved = try fixture.folder.loadEdit()
        try await wait { !model.isPreparing && model.edit?.revision == saved.revision && model.poster != nil }
        #expect(model.player.currentItem !== initialItem, "A resize deliberately changes the preview scale and replaces its item.")
        #expect(model.edit?.main.first?.cameraTransform == PictureTransform(centerX: 0.25, centerY: 0.75, zoom: 1.8))
        #expect(try fixture.folder.history.entries().count == historyCount + 1)
        #expect(model.problem == nil && model.previewProblem == nil)
        model.undo()
        try await wait { !model.isPreparing && (model.edit?.revision ?? 0) > saved.revision }
        #expect(model.edit?.main == before.main)
        #expect(try fixture.folder.history.entries().count == historyCount)
    }

    @Test func reloadsPublishHistoryAndRedoAlongsideFramingMixAndTimelineChanges() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        defer { model.player.replaceCurrentItem(with: nil) }
        await model.reload()
        let clip = try #require(model.edit?.main.first?.id)
        for kind in 0..<3 {
            try fixture.folder.updateEdit(author: .app, reason: "History fixture \(kind)") { edit in
                switch kind {
                case 0: try edit.setTransform(.init(zoom: 1.7), picture: .camera, for: [clip])
                case 1: try edit.setSound(.init(voiceLevel: -9), for: [clip])
                default: try edit.split(at: 1)
                }
            }
            await model.reload()
            #expect(model.history == (try fixture.folder.history.entries()))
            #expect(model.canRedo == fixture.folder.canRedo)
            #expect(model.edit == (try fixture.folder.loadEdit()))
            try fixture.folder.undo()
            await model.reload()
            #expect(model.history == (try fixture.folder.history.entries()))
            #expect(model.canRedo)
            try fixture.folder.redo(author: .app)
            await model.reload()
            #expect(model.history == (try fixture.folder.history.entries()))
            #expect(!model.canRedo)
        }
    }

    @Test func anUnchangedMixedFramingScrubRestoresThePictureAndPreservesFeedbackAndHistory() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try fixture.folder.updateEdit(author: .app, reason: "Mixed framing fixture") { edit in
            try edit.split(at: 1)
            let first = try #require(edit.main.first?.id), last = try #require(edit.main.last?.id)
            try edit.setTransform(.init(zoom: 1.2), picture: .camera, for: [first])
            try edit.setTransform(.init(zoom: 2), picture: .camera, for: [last])
        }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        defer { model.cancelTransformPreview(); model.player.replaceCurrentItem(with: nil) }
        model.selection = .clips(Set(try #require(model.edit).main.map(\.id)))
        let before = try fixture.folder.loadEdit()
        let history = try fixture.folder.history.entries()
        model.notice = "QA notice"
        model.problem = "QA problem"
        model.previewTransform(picture: .camera, zoom: 2.5)
        let audition = model.player.currentItem?.videoComposition
        let field = InspectorNumberField.NumberField()
        field.commit = { model.setTransform(picture: .camera, zoom: $0 / 100) }
        field.cancelPreview = { model.cancelTransformPreview() }
        field.finishScrub(at: 100, startingAt: 100, original: nil)
        #expect(model.player.currentItem?.videoComposition !== audition)
        #expect(model.notice == "QA notice" && model.problem == "QA problem")
        #expect(try fixture.folder.loadEdit() == before)
        #expect(try fixture.folder.history.entries() == history)
    }

    @Test func unrelatedBackgroundFilesDoNotRedrawAnUnchangedPicture() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        defer { model.player.replaceCurrentItem(with: nil) }
        model.seek(to: 0.6)
        try await wait { abs(model.player.currentTime().seconds - 0.6) < model.frameDuration }
        let item = try #require(model.player.currentItem)
        let picture = item.videoComposition
        let edit = try fixture.folder.loadEdit()
        try Data("Unrelated QA metadata".utf8).write(to: fixture.folder.url(for: .screen).appending(path: "qa-background.txt"))
        await model.reload()
        #expect(model.player.currentItem === item)
        #expect(item.videoComposition === picture, "An unrelated file update must not invalidate the decoded picture or schedule a new framing seek.")
        #expect(abs(model.currentTime - 0.6) < model.frameDuration)
        #expect(try fixture.folder.loadEdit() == edit)
    }

    @Test func aReloadKeepsTheInspectorTabChosenWhileAClipIsSelected() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        defer { model.player.replaceCurrentItem(with: nil) }
        let id = try #require(model.edit?.main.first?.id)
        model.selection = .clips([id])
        // The transcript stays reachable with a clip selected, and cutting words there reloads the edit.
        model.inspectorTab = .transcript
        try fixture.folder.updateEdit(author: .app, reason: "A change made from the transcript") { try $0.setSound(.init(voiceLevel: -6), for: [id]) }
        await model.reload()
        #expect(model.selection == .clips([id]))
        #expect(model.inspectorTab == .transcript, "A reload must not move the inspector off the tab the creator chose.")
        model.selection = .none
        model.selection = .clips([id])
        #expect(model.inspectorTab == .video, "Selecting a clip still shows its settings.")
    }

    @Test func aReloadDuringAHeldFramingDragKeepsWhatIsBeingAuditioned() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        defer { model.cancelTransformPreview(); model.player.replaceCurrentItem(with: nil) }
        let id = try #require(model.edit?.main.first?.id)
        model.selection = .clips([id])
        let item = try #require(model.player.currentItem)
        model.isPointerDown = { true }
        model.previewTransform(picture: .camera, zoom: 2)
        try fixture.folder.updateEdit(author: .app, reason: "Cleaning finished mid-drag") { try $0.setSound(.init(voiceLevel: -18), for: [id]) }
        await model.reload()
        #expect(model.player.currentItem === item)
        #expect(model.edit?.main.first?.voiceLevel == -18)
        let held = item.videoComposition
        model.cancelTransformPreview()
        #expect(item.videoComposition !== held, "The drag's picture must still be on screen after the reload, until the drag ends.")
        #expect(model.edit?.main.first?.cameraTransform == nil)
    }

    @Test func anAudioMixReloadCannotLeaveAnAbandonedFramingAuditionOnScreen() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        defer { model.player.replaceCurrentItem(with: nil) }
        let id = try #require(model.edit?.main.first?.id)
        model.selection = .clips([id])
        let item = try #require(model.player.currentItem)
        model.previewTransform(picture: .camera, zoom: 2)
        let audition = item.videoComposition
        try fixture.folder.updateEdit(author: .app, reason: "QA background mix update") { try $0.setSound(.init(voiceLevel: -18), for: [id]) }
        await model.reload()
        #expect(model.player.currentItem === item)
        #expect(item.videoComposition !== audition, "An audio-only reload must restore a cancelled crop before retaining the picture item.")
        #expect(model.edit?.main.first?.voiceLevel == -18)
        #expect(model.edit?.main.first?.cameraTransform == nil)
    }

    @Test func closingEditorsDuringPreparationFramingAndNormalizationReleasesTheirModels() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        for mode in 0..<12 {
            let released = try await openThenClose(fixture.folder, mode: mode % 3)
            try await wait { released.value == nil }
        }
    }

    private func openThenClose(_ folder: ProjectFolder, mode: Int) async throws -> WeakModel {
        let model = EditorModel(folder: folder)
        model.player.isMuted = true
        let released = WeakModel(model)
        let watcher = Task { await model.watch() }
        defer { watcher.cancel() }
        if mode == 0 {
            await Task.yield()
        } else {
            try await wait { !model.isPreparing && model.poster != nil }
            if mode == 1 {
                model.selection = .clips([try #require(model.edit?.main.first?.id)])
                model.previewTransform(picture: .camera, centerX: 0.2, zoom: 2)
                model.previewHeightChanged(toPixels: 1800)
            } else {
                model.normalizePreview = true
            }
        }
        watcher.cancel()
        await watcher.value
        return released
    }

    private final class WeakModel {
        weak var value: EditorModel?
        init(_ value: EditorModel) { self.value = value }
    }

    @Test func replacingMediaHoldsThePictureUntilTheNewClockIsReady() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        let item = try #require(model.player.currentItem)
        #expect(model.displayReadyItem === item)
        let view = PanelPlayerView(frame: .init(x: 0, y: 0, width: 320, height: 180))
        let window = NSWindow(contentRect: .init(x: -10_000, y: -10_000, width: 320, height: 180),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { view.player = nil; window.close(); model.player.replaceCurrentItem(with: nil) }
        view.hold = model.frameHold
        view.show(model.poster)
        view.player = model.player
        view.displayReadyItem = item
        model.seek(to: 0.6)
        try await wait { view.playerLayer.isReadyForDisplay }
        try await wait { !view.playerLayer.isHidden }
        model.frameHold.capture(from: item)
        try await wait {
            model.frameHold.capture(from: item)
            return model.frameHold.image != nil
        }
        let held = try #require(model.frameHold.image)
        model.frameHold.capture(from: nil)
        #expect(model.frameHold.image === held, "A replacement without a decoded frame must retain the previous picture.")
        let replacement = AVPlayerItem(asset: item.asset)
        replacement.videoComposition = item.videoComposition
        model.player.replaceCurrentItem(with: replacement)
        #expect(view.playerLayer.isHidden, "The old ready flag must not expose a replacement before its seek.")
        #expect(!view.posterLayer.isHidden)
        #expect(view.posterLayer.contents != nil)
        await model.player.seek(to: CMTime(seconds: 0.6, preferredTimescale: 600))
        try await wait { view.playerLayer.isReadyForDisplay }
        #expect(view.playerLayer.isHidden, "Readiness alone is insufficient until this item's exact seek completes.")
        view.displayReadyItem = replacement
        #expect(!view.playerLayer.isHidden)
    }

    @Test func framingAuditionsKeepThePlayingItemClockAndEditUntilOneCommit() async throws {
        let fixture = try await Fixture(cameraOffset: 0.25)
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        model.selection = .clips([try #require(model.edit?.main.first?.id)])
        let item = try #require(model.player.currentItem)
        let beforeVideo = item.videoComposition
        let original = try fixture.folder.loadEdit()
        let history = try fixture.folder.history.entries()
        for value in [1.2, 1.4, 1.6] { model.previewTransform(picture: .camera, zoom: value) }
        #expect(model.player.currentItem === item)
        #expect(item.videoComposition !== beforeVideo)
        #expect(model.currentTime == 0)
        #expect(try fixture.folder.loadEdit() == original)
        #expect(try fixture.folder.history.entries() == history)
        model.cancelTransformPreview()
        try await wait { model.player.currentTime() == .zero }
        #expect(try fixture.folder.loadEdit() == original)
        model.previewTransform(picture: .camera, zoom: 1.8)
        model.setTransform(picture: .camera, zoom: 1.8)
        try await wait { model.edit?.main.first?.cameraTransform?.zoom == 1.8 }
        #expect(model.player.currentItem === item, "A framing commit should replace instructions, not media tracks.")
        #expect(model.currentTime == 0)
        #expect(try fixture.folder.history.entries().count == history.count + 1)
        model.cancelTransformPreview()
        model.player.replaceCurrentItem(with: nil)
    }

    @Test func switchingOutputRebuildsThePictureEvenWhenTheEditAndMixAreUnchanged() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        try fixture.folder.updateProject { $0.format = VideoFormat(destination: .both) }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        defer { model.player.replaceCurrentItem(with: nil) }
        let before = try fixture.folder.loadEdit()
        for shape in [OutputShape.vertical, .landscape, .vertical] {
            let previous = model.player.currentItem
            model.show(shape)
            try await wait { !model.isPreparing && model.panels.map(\.output) == [shape] && model.poster != nil }
            #expect(model.player.currentItem !== previous, "A new output must install its picture rather than only updating the audio mix.")
            #expect(model.shape == shape)
            let panel = try #require(model.panels.first?.rect)
            #expect(abs(Double(panel.width / panel.height) - Double(shape.width) / Double(shape.height)) < 0.000_001)
            #expect(model.player.currentItem?.videoComposition?.renderSize == model.renderSize)
            #expect(model.currentTime == 0 && model.player.currentTime() == .zero)
        }
        #expect(try fixture.folder.loadEdit() == before)
    }

    @Test func returningAFramingAdjustmentToItsStartingValueRestoresThePersistedPicture() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        model.selection = .clips([try #require(model.edit?.main.first?.id)])
        let item = try #require(model.player.currentItem)
        defer { model.cancelTransformPreview(); model.player.replaceCurrentItem(with: nil) }
        let before = try fixture.folder.loadEdit()
        let history = try fixture.folder.history.entries()
        model.previewTransform(picture: .camera, zoom: 1.8)
        let audition = item.videoComposition
        // A slider can finish on its original value after its last preview update was coalesced.
        model.setTransform(picture: .camera, zoom: 1)
        #expect(item.videoComposition !== audition, "An unchanged commit must restore the saved crop instead of leaving an audition on screen.")
        let restored = item.videoComposition
        model.cancelTransformPreview()
        #expect(item.videoComposition === restored, "The completed adjustment must leave no outstanding audition.")
        #expect(model.player.currentItem === item)
        #expect(try fixture.folder.loadEdit() == before)
        #expect(try fixture.folder.history.entries() == history)
    }

    /// A camera that starts late holds its first frame from zero, so there's no gap to step around
    /// (docs/decisions.md, 87): the playhead, the player and the poster are all at zero.
    @Test func aCameraThatStartsLateNeverMovesTheTimelineOrigin() async throws {
        let fixture = try await Fixture(cameraOffset: 0.25)
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing && model.poster != nil }
        #expect(model.currentTime == 0)
        #expect(model.player.currentTime() == .zero)
        model.normalizePreview = true
        try await wait { !model.previewLoudness.isPreparing && !model.isPreparing }
        #expect(model.currentTime == 0 && model.player.currentTime() == .zero)
        model.normalizePreview = false
        try await wait { !model.isPreparing }
        model.seek(to: 0.6)
        try await wait { abs(model.player.currentTime().seconds - 0.6) < model.frameDuration }
        model.seek(to: 0)
        try await wait { model.player.currentTime() == .zero }
        #expect(model.currentTime == 0)
        model.step(frames: -1)
        #expect(model.currentTime == 0)
        model.step(frames: 1)
        #expect(abs(model.currentTime - model.frameDuration) < 0.000_001)
        model.step(frames: -1)
        #expect(model.currentTime == 0)
        model.pause()
        #expect(model.currentTime == 0)
        await model.reload()
        try await wait { !model.isPreparing }
        #expect(model.currentTime == 0, "Rebuilding must preserve a zero playhead.")
        model.player.replaceCurrentItem(with: nil)
    }

    @Test(arguments: [false, true])
    func enablingLoudnessAfterAnEmptyOrFailedPreviewFinishesWithoutWaiting(brokenMedia: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        if brokenMedia {
            try FileManager.default.removeItem(at: fixture.folder.url(for: .recordings).appending(path: "camera.mov"))
        } else {
            try fixture.folder.updateEdit(author: .app, reason: "Empty fixture") { $0.main = [] }
        }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        model.normalizePreview = true
        #expect(!model.previewLoudness.isPreparing)
        if brokenMedia {
            if case .failed = model.previewLoudness.state {} else { Issue.record("Missing media must report the preview's failure.") }
        } else {
            if case .ready(_, hasAudio: false) = model.previewLoudness.state {} else { Issue.record("An empty edit has no sound to normalize.") }
        }
        model.normalizePreview = false
        #expect(model.player.currentItem == nil)
    }
    @Test func loudnessAuditionPreservesPositionAndDoesNotWriteAnEdit() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing }
        model.seek(to: 0.6)
        try await wait { abs(model.player.currentTime().seconds - 0.6) < model.frameDuration }
        let original = try #require(model.player.currentItem)
        let edit = try Data(contentsOf: fixture.folder.editFileURL)
        let history = try fixture.folder.history.entries()
        model.normalizePreview = true
        try await wait { !model.previewLoudness.isPreparing && !model.isPreparing }
        guard case .ready(_, hasAudio: true) = model.previewLoudness.state else {
            Issue.record("A valid mic mix must become a ready normalized preview: \(model.previewLoudness.state)")
            return
        }
        #expect(model.player.currentItem !== original)
        #expect(abs(model.currentTime - 0.6) < model.frameDuration)
        #expect(abs(model.player.currentTime().seconds - 0.6) < model.frameDuration)
        model.normalizePreview = false
        try await wait { !model.isPreparing }
        #expect(model.previewLoudness.state == .off)
        #expect(abs(model.player.currentTime().seconds - 0.6) < model.frameDuration)
        model.normalizePreview = true
        try await wait { !model.previewLoudness.isPreparing && !model.isPreparing }
        #expect(try Data(contentsOf: fixture.folder.editFileURL) == edit)
        #expect(try fixture.folder.history.entries() == history)
        model.normalizePreview = false
        model.player.replaceCurrentItem(with: nil)
    }

    @Test func changingTheMixReplacesNormalizedAudioAndEmptyingTheEditCannotRestoreStaleSound() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        await model.reload()
        try await wait { !model.isPreparing }
        model.normalizePreview = true
        try await wait { !model.previewLoudness.isPreparing && !model.isPreparing }
        let before = try #require(model.player.currentItem)
        let id = try #require(model.edit?.main.first?.id)
        try fixture.folder.updateEdit(author: .app, reason: "QA quieter voice") { try $0.setSound(.init(voiceLevel: -18), for: [id]) }
        await model.reload()
        try await wait { !model.previewLoudness.isPreparing && !model.isPreparing }
        #expect(model.timeline?.clips.first?.clip.voiceLevel == -18)
        #expect(model.player.currentItem !== before)
        guard case .ready(_, hasAudio: true) = model.previewLoudness.state else { Issue.record("The new mix must be normalized"); return }
        try fixture.folder.updateEdit(author: .app, reason: "QA empty edit") { try $0.removeClip(id) }
        await model.reload()
        #expect(model.player.currentItem == nil)
        #expect(model.timeline == nil)
        guard case .ready(_, hasAudio: false) = model.previewLoudness.state else { Issue.record("An empty edit must finish without sound"); return }
        model.normalizePreview = false
        #expect(model.player.currentItem == nil, "Disabling audition must never restore a composition from a deleted clip.")
    }

    @Test func waveformsKeepRawPeaksTheLastPartialBinAndTheProcessedAudioFile() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let model = EditorModel(folder: fixture.folder)
        model.loadForPreview()
        try await wait { model.waveforms[fixture.source.id] != nil }
        let raw = try #require(model.waveforms[fixture.source.id])
        #expect(abs(Double(raw.peak(at: 0.5)) - 0.1) < 0.005)
        let name = "\(fixture.source.id)-qa-cleaned.wav"
        let cleaned = fixture.folder.url(for: .audio).appending(path: name)
        try Fixture.writeSound(cleaned, peak: 0.4, count: 96_480)
        try fixture.folder.saveCleanedAudio(.init(source: fixture.source.id,
            settings: fixture.folder.loadEdit().audio.settings(for: fixture.source.id), file: name,
            original: try #require(fixture.source.primaryAudioTrack?.file)))
        model.loadForPreview()
        try await wait { (model.waveforms[fixture.source.id]?.peak(at: 0.5) ?? 0) > 0.3 }
        let processed = try #require(model.waveforms[fixture.source.id])
        #expect(abs(Double(processed.peak(at: 0.5)) - 0.4) < 0.005)
        #expect(processed.peaks.count == 101, "The last ten milliseconds need a waveform too.")
        #expect(processed.peak(at: 2.005) > 0.3)
        let offset = try #require(await Waveform.load(cleaned, startOffset: 0.25))
        #expect(offset.peak(at: 0.1) == 0)
        #expect(offset.peak(at: 0.75) > 0.3)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while !condition() {
            guard clock.now < deadline else { throw NSError(domain: "AudioPreviewTests", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for preview audio"]) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct Fixture {
        let folder: ProjectFolder
        let source: Source
        init(cameraOffset: Double = 0) async throws {
            folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-audio-preview-test-\(UUID())"), title: "Audio preview fixture")
            try Self.writeSound(folder.url(for: .recordings).appending(path: "mic.wav"), peak: 0.1, count: 96_480)
            try await Self.writeVideo(folder.url(for: .recordings).appending(path: "camera.mov"))
            let project = try folder.updateProject { project in
                project.addSource(name: "Fixture take", origin: .recorded, tracks: [
                    SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), startOffset: cameraOffset,
                        media: MediaInfo(duration: 2.01, video: .init(width: 64, height: 64, frameRate: 30, captureRate: 30, codec: "avc1"))),
                    SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"),
                                media: MediaInfo(duration: 2.01, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
                ])
            }
            source = try #require(project.sources.first)
            let source = source
            try folder.updateEdit(author: .app, reason: "Fixture") { edit in
                edit.addWholeSource(source)
            }
        }
        static func writeVideo(_ url: URL) async throws {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video,
                outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
            writer.add(input)
            #expect(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<61 {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
                let pool = try #require(adaptor.pixelBufferPool)
                var buffer: CVPixelBuffer?
                #expect(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess)
                let pixels = try #require(buffer)
                CVPixelBufferLockBaseAddress(pixels, [])
                if let base = CVPixelBufferGetBaseAddress(pixels) {
                    memset(base, 128, CVPixelBufferGetBytesPerRow(pixels) * 64)
                }
                CVPixelBufferUnlockBaseAddress(pixels, [])
                #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
            }
            input.markAsFinished()
            await writer.finishWriting()
            #expect(writer.status == .completed)
        }
        static func writeSound(_ url: URL, peak: Float, count: Int) throws {
            let writer = try WAVStreamWriter(url: url, sampleRate: 48_000)
            try writer.append((0..<count).map { peak * Float(sin(2 * Double.pi * 220 * Double($0) / 48_000)) })
            try writer.finish()
        }
        func remove() { try? FileManager.default.removeItem(at: folder.url) }
    }
}

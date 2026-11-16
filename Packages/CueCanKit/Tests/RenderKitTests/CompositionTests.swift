import AVFoundation
import Foundation
import Testing
import ProjectKit
@testable import RenderKit

/// The composition end to end on synthetic files: a red 32:27 screen, a blue camera and a tone for the mic.
@Suite(.serialized) struct CompositionTests {
    let folder: ProjectFolder

    init() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-render-\(UUID().uuidString)")
        folder = try ProjectFolder.create(at: url, title: "Render test")
        let recordings = folder.url(for: .recordings)
        try await SyntheticMedia.writeVideo(SyntheticMedia.red, width: 640, height: 540, seconds: 6, to: recordings.appending(path: "screen.mov"))
        try await SyntheticMedia.writeVideo(SyntheticMedia.blue, width: 320, height: 180, seconds: 6, to: recordings.appending(path: "camera.mov"))
        try SyntheticMedia.writeTone(seconds: 6, to: recordings.appending(path: "mic.wav"))
        try folder.updateProject { project in
            project.addSource(
                name: "Screen recording",
                origin: .recorded,
                tracks: [
                    SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: 6, video: .init(width: 640, height: 540, frameRate: 30, captureRate: 30, codec: "avc1"))),
                    SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), media: MediaInfo(duration: 6, video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1"))),
                    SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), media: MediaInfo(duration: 6, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
                ],
                captureArea: CaptureArea(ratio: .thirtyTwoByTwentySeven, heightPoints: 270),
                layout: .sideBySide(.thirtyTwoByTwentySeven)
            )
        }
        _ = try folder.addTranscript(speech.draft, for: SourceID(number: 1))
        try folder.updateEdit(author: .system("Test"), reason: "Two clips") { edit in
            edit.main = [clip(1, 0.95, 1.9), clip(2, 2.95, 4.2)]
            // Edge to edge, so the pixels below are where the tiles' own edges would be.
            edit.look.inset = .none
        }
    }

    @Test func sideBySidePutsTheScreenLeftAndTheCameraRight() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        #expect(abs(built.composition.duration.seconds - 2.2) < 0.01)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [0.5], maximumWidth: 960).first)
        #expect(still.width == 960 && still.height == 540)
        // The screen is 1280 of 1920 wide: 640 of 960 here.
        #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
    }

    @Test func previewPosterIncludesTheFirstFrameWithoutPlayback() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [0], maximumWidth: 960).first)
        #expect(still.time == 0)
        #expect(still.width == 960 && still.height == 540)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
    }

    @Test func cancellingStillsDoesNotLeaveAReaderRunning() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let read = Task { try await FrameGrabber.stills(of: built, at: Array(repeating: 0.5, count: 100)) }
        await Task.yield()
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
    }

    @Test func aBackgroundPosterUsesIndependentCompositionObjects() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let copy = try built.copyForReading()
        #expect(copy.composition !== built.composition)
        #expect(copy.videoComposition !== built.videoComposition)
        #expect(copy.audioMix !== built.audioMix)
        #expect(copy.timeline.duration == built.timeline.duration)
        let still = try #require(try await FrameGrabber.stills(of: copy, at: [0.5]).first)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
    }

    @Test func aHeldScreenAfterASpeedChangeCanBeReadAtPreviewScale() async throws {
        try folder.updateEdit(author: .app, reason: "Preview regression") { edit in
            edit.main = [clip(1, 0, 2), clip(2, 2, 6)]
            _ = try edit.setSpeed(ClipSpeed(rate: 1.5) ?? .normal, for: ClipID(number: 1))
            _ = try edit.freeze(timeline: TimeRange(start: 2, end: 4))
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape, scale: 0.75)
        let stills = try await FrameGrabber.stills(of: built, at: [2.231, 3.237])
        #expect(stills.count == 2)
        for still in stills {
            #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
        }
    }

    /// A take's files are cut to start together (docs/decisions.md, 87). Where one still starts late, or a
    /// changed lip sync moves the camera off the take's ends, its nearest frame is held: no tile is empty.
    @Test func aPictureThatStartsLateOrEndsEarlyHoldsItsNearestFrame() async throws {
        try folder.updateProject { project in
            project.sources[0].tracks[0].startOffset = 0.3
            project.sources[0].tracks[1].startOffset = 0.5
        }
        try folder.updateEdit(author: .system("Test"), reason: "The whole take, and past the camera's end") {
            $0.main = [clip(1, 0, 6.2)]
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        #expect(built.timeline.clips[0].timeline.start == 0)
        // Before either picture's first frame, between the two, in the take, and past the screen's end.
        let stills = try await FrameGrabber.stills(of: built, at: [0, 0.4, 3, 6.15])
        #expect(stills.map(\.time).first == 0)
        for still in stills {
            #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true, "The screen at \(still.time)")
            #expect(SyntheticMedia.pixel(still.jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true, "The camera at \(still.time)")
        }
        // One picture lane each, with no empty stretch in it, and nothing running past the clip.
        for track in built.composition.tracks(withMediaType: .video) {
            let segments = try await track.load(.segments)
            #expect(!segments.contains { $0.isEmpty })
            #expect(abs((segments.last?.timeMapping.target.end.seconds ?? 0) - 6.2) < 0.001)
        }
        #expect(abs(built.composition.duration.seconds - 6.2) < 0.001)
    }

    @Test func aShortStacksTheCameraAboveTheScreen() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .vertical)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [1.5], maximumWidth: 540).first)
        #expect(still.width == 540 && still.height == 960)
        // The 27:32 slot for a 32:27 screen: the screen fits the width, 455 tall at the bottom; camera above.
        #expect(SyntheticMedia.pixel(still.jpeg, x: 270, y: 900)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 270, y: 100)?.isClose(to: SyntheticMedia.blue) == true)
    }

    @Test func theLookInsetsTheTilesOnItsBackground() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Look") { edit in
            edit.look = EditLook(background: "#00FF00")
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [0.5], maximumWidth: 960).first)
        // Inset M is 60 px of 1920, 30 here: the edge is the green background, the tiles inside it.
        #expect(SyntheticMedia.pixel(still.jpeg, x: 10, y: 270)?.isClose(to: SyntheticMedia.green) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 10)?.isClose(to: SyntheticMedia.green) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
        // A rounded corner shows the background where a square one would show the screen.
        #expect(SyntheticMedia.pixel(still.jpeg, x: 32, y: 32)?.isClose(to: SyntheticMedia.green) == true)

    }

    /// A still of the test take in a base look with add-ons, at Inset M, 960 wide.
    private func still(in backdrop: OutputLook.Backdrop, _ addOns: Set<OutputLook.AddOn> = [], at time: Double = 0.5) async throws -> Data {
        try folder.updateEdit(author: .system("Test"), reason: "Look") { edit in
            edit.look = EditLook(background: "#00FF00", backdrop: backdrop, addOns: addOns)
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        return try #require(try await FrameGrabber.stills(of: built, at: [time], maximumWidth: 960).first).jpeg
    }

    private func brightness(_ jpeg: Data, x: Int, y: Int) throws -> Int {
        let pixel = try #require(SyntheticMedia.pixel(jpeg, x: x, y: y))
        return Int(pixel.red) + Int(pixel.green) + Int(pixel.blue)
    }

    @Test func aBaseLookIsItsOwnBackgroundAndShadowsAreAnAddOn() async throws {
        let paper = try await still(in: .paper), shadowed = try await still(in: .paper, [.shadows]), ink = try await still(in: .ink)
        // The frame's corner is the base look's background, never the look's plain green.
        #expect(try brightness(paper, x: 4, y: 4) > 740)
        #expect(try brightness(ink, x: 4, y: 4) < 70)
        // Just under the screen: plain white without shadows; with them darker, and still nearly white.
        #expect(try brightness(paper, x: 300, y: 516) > 740)
        let under = try brightness(shadowed, x: 300, y: 516)
        #expect(under < 740 - 12 && under > 560, "Under the screen is \(under).")
        // The tiles are drawn over it as before.
        for jpeg in [paper, shadowed, ink] {
            #expect(SyntheticMedia.pixel(jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
            #expect(SyntheticMedia.pixel(jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
        }
    }

    @Test func daylightSwingsTheShadowAcrossTheGapBetweenTheTiles() async throws {
        // A quarter of the way through, the light is far left and the screen's shadow falls right; at three
        // quarters it falls left.
        let quarter = TileShadow.daylightPeriod / 4
        #expect(TileShadow.lightPosition(at: quarter) < -0.99)
        let layers = TileShadow.layers(dark: false, moving: true, at: quarter)
        #expect(layers[0].x > 0.029 && TileShadow.layers(dark: false, moving: true, at: quarter * 3)[0].x < -0.029)
        #expect(TileShadow.layers(dark: false, moving: false, at: quarter)[0].x == 0)
        // The warm band is under the light.
        #expect(DaylightBand.center(at: quarter) < 0.2 && DaylightBand.center(at: quarter * 3) > 0.8)
        let still = try await still(in: .daylight, [.shadows], at: 0.5)
        #expect(SyntheticMedia.pixel(still, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
    }

    @Test func auraAndGlowBloomWithTheCamerasOwnColours() async throws {
        let aura = try await still(in: .aura), glow = try await still(in: .glow)
        // Right of the blue camera: on white, less red and green than blue; on near-black, more blue than either.
        let pale = try #require(SyntheticMedia.pixel(aura, x: 952, y: 270))
        #expect(pale.blue > pale.red && pale.blue > 200, "Aura beside the camera is \(pale).")
        let deep = try #require(SyntheticMedia.pixel(glow, x: 952, y: 270))
        #expect(deep.blue > deep.red && deep.blue > deep.green && deep.blue > 40 && deep.blue < 200, "Glow beside the camera is \(deep).")
        // The bloom is the camera's alone: far left of the red screen stays the near-black background.
        let left = try #require(SyntheticMedia.pixel(glow, x: 8, y: 270))
        #expect(left.red < 60 && left.blue < 80, "Glow left of the screen is \(left).")
        #expect(SyntheticMedia.pixel(glow, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
    }

    @Test func theLitEdgeLeavesTheTilesThemselves() async throws {
        let edged = try await still(in: .ink, [.litEdge])
        #expect(SyntheticMedia.pixel(edged, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(edged, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
    }

    @Test func theInsetIsTheSameInEveryClip() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Inset") { edit in
            edit.look = EditLook(inset: .medium, background: "#00FF00")
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let stills = try await FrameGrabber.stills(of: built, at: [0.5, 1.5], maximumWidth: 960)
        // Both clips are inset on the green background (docs/decisions.md, 86).
        for still in stills {
            #expect(SyntheticMedia.pixel(still.jpeg, x: 10, y: 270)?.isClose(to: SyntheticMedia.green) == true)
        }
    }

    @Test func flippingPutsTheCameraOnTheLeft() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Flip") { edit in
            for index in edit.main.indices { edit.main[index].look.cameraSide = .flipped }
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [0.5], maximumWidth: 960).first)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 160, y: 270)?.isClose(to: SyntheticMedia.blue) == true)
        #expect(SyntheticMedia.pixel(still.jpeg, x: 640, y: 270)?.isClose(to: SyntheticMedia.red) == true)
    }

    @Test func bothOutputsPlaySideBySideInOneComposition() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), outputs: [.landscape, .vertical])
        #expect(built.videoComposition.renderSize == CGSize(width: 2528, height: 1080))
        #expect(built.rect(of: .vertical)?.isClose(to: CGRect(x: 1920, y: 0, width: 607.5, height: 1080)) == true)
        let short = try #require(try await FrameGrabber.stills(of: built, at: [0.5], maximumWidth: 304, output: .vertical).first)
        #expect(abs(short.width - 304) <= 1 && abs(short.height - 540) <= 1, "\(short.width) × \(short.height)")
        #expect(SyntheticMedia.pixel(short.jpeg, x: 150, y: 500)?.isClose(to: SyntheticMedia.red) == true)
        #expect(SyntheticMedia.pixel(short.jpeg, x: 150, y: 40)?.isClose(to: SyntheticMedia.blue) == true)
    }

    @Test func aStillOverlayTakesTheScreensPlace() async throws {
        let picture = folder.url.appending(path: "shot.png")
        try SyntheticMedia.writePNG(SyntheticMedia.green, width: 64, height: 54, to: picture)
        try folder.updateEdit(author: .system("Test"), reason: "Overlay") { edit in
            _ = try edit.placeOverlay(.file(at: picture), overTimeline: TimeRange(start: 0.2, end: 0.8), placement: .inScreensPlace)
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let stills = try await FrameGrabber.stills(of: built, at: [0.5, 1.5], maximumWidth: 960)
        #expect(SyntheticMedia.pixel(stills[0].jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.green) == true)
        #expect(SyntheticMedia.pixel(stills[0].jpeg, x: 800, y: 270)?.isClose(to: SyntheticMedia.blue) == true, "The camera stays.")
        #expect(SyntheticMedia.pixel(stills[1].jpeg, x: 300, y: 270)?.isClose(to: SyntheticMedia.red) == true, "After it, the screen again.")
    }

    @Test func speedAndFreezesRetimeThePicture() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Retime") { edit in
            edit.main[1].speed = ClipSpeed(rate: 2, sound: .pitchKept)!
            _ = try edit.freeze(timeline: TimeRange(start: 0.2, end: 0.6))
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        #expect(abs(built.composition.duration.seconds - (0.95 + 1.25 / 2)) < 0.02)
        let screen = try #require(built.composition.tracks(withMediaType: .video).first)
        let held = screen.segments.first { segment in
            !segment.isEmpty && segment.timeMapping.source.duration.seconds < 0.05 && segment.timeMapping.target.duration.seconds > 0.3
        }
        #expect(held != nil, "One frame of the screen is stretched over the freeze.")
        #expect(abs((held?.timeMapping.target.start.seconds ?? 0) - 0.2) < 0.01)
        let mix = try await AudioMixRenderer.render(built)
        #expect(abs(Double(mix.count) / 48_000 - built.timeline.duration) < 0.01, "The voice plays on through the freeze, and faster in the sped-up clip.")
    }

    @Test func mutedClipsAndLevelsSetTheMix() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Mute") { edit in
            edit.main[0].isMuted = true
            edit.main[1].voiceLevel = -6
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let mix = try await AudioMixRenderer.render(built)
        let firstClip = mix.prefix(Int(0.9 * 48_000)).map(abs).max() ?? 1
        let secondClip = mix.dropFirst(Int(1.1 * 48_000)).map(abs).max() ?? 0
        #expect(firstClip < 0.001, "A muted clip is silent.")
        #expect(secondClip > 0.03 && secondClip < 0.07, "−6 dB on a 0.1 tone is about 0.05.")
    }

    @Test func eachClipPlaysAtItsOwnLevel() async throws {
        // docs/decisions.md, 71: the first clip turned down 20 dB, the second as recorded.
        try folder.updateEdit(author: .system("Test"), reason: "Levels") { edit in
            try edit.setSound(ClipSoundChange(voiceLevel: -20), for: [edit.main[0].id])
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let mix = try await AudioMixRenderer.render(built)
        let firstClip = mix.prefix(Int(0.9 * 48_000)).map(abs).max() ?? 1
        let secondClip = mix.dropFirst(Int(1.1 * 48_000)).map(abs).max() ?? 0
        #expect(firstClip > 0.007 && firstClip < 0.013, "−20 dB on a 0.1 tone is about 0.01.")
        #expect(secondClip > 0.07, "The second clip plays as recorded.")
    }

    @Test func aChangeOfLevelsKeepsTheCompositionsTracks() async throws {
        // docs/decisions.md, 71: the playing preview takes a new mix without being rebuilt, so the new mix
        // has to name the tracks the playing item already has.
        let before = try RenderInputs.load(folder)
        try folder.updateEdit(author: .system("Test"), reason: "Levels") { edit in
            try edit.setSound(ClipSoundChange(voiceLevel: -9, systemAudioLevel: -20), for: [edit.main[0].id])
            edit.audio.defaults.voice.preset = .broadcast
        }
        let after = try RenderInputs.load(folder)
        #expect(after.differsOnlyInMix(from: before))
        let source = try #require(before.project.sources.first)
        let audio = try #require(source.primaryAudioTrack)
        try folder.saveLevels(SourceLevels(source: source.id, original: audio.file, detector: "test", threshold: -50,
                                           minimumSound: 0.03, envelope: SoundEnvelope(levels: [-60, -20], frameDuration: 0.01)))
        #expect(!(try RenderInputs.load(folder)).differsOnlyInMix(from: after), "New word-onset levels change caption pictures too.")
        let first = try await CompositionBuilder.build(before, output: .landscape)
        let second = try await CompositionBuilder.build(after, output: .landscape)
        #expect(first.composition.tracks.map(\.trackID) == second.composition.tracks.map(\.trackID))
        let mixed = Set(second.audioMix.inputParameters.map(\.trackID))
        #expect(!mixed.isEmpty && mixed.isSubset(of: Set(first.composition.tracks(withMediaType: .audio).map(\.trackID))))

        try folder.updateEdit(author: .system("Test"), reason: "Mute") { edit in edit.main[0].isMuted = true }
        #expect(!(try RenderInputs.load(folder)).differsOnlyInMix(from: after), "Mute takes a track away.")
        try folder.updateEdit(author: .system("Test"), reason: "Unmute, then move") { edit in
            edit.main[0].isMuted = false
            edit.main[0].sourceOut -= 0.1
        }
        #expect(!(try RenderInputs.load(folder)).differsOnlyInMix(from: after), "A moved edge changes the picture.")
    }

    @Test func thePreviewKeepsTheLastCleaningWhileTheVoiceIsCleanedAgain() throws {
        let source = SourceID(number: 1)
        let track = try #require(try folder.loadProject().source(source)?.primaryAudioTrack)
        let settings = try folder.loadEdit().audio.settings(for: source)
        let cleaned = folder.url(for: .audio).appending(path: "\(source)-first.wav")
        try FileManager.default.copyItem(at: track.file.url(relativeTo: folder.url), to: cleaned)
        try folder.saveCleanedAudio(.init(source: source, settings: settings, file: cleaned.lastPathComponent, original: track.file))
        #expect(try RenderInputs.load(folder).primaryAudio[source] == cleaned)
        try folder.updateEdit(author: .system("Test"), reason: "Voice") { edit in edit.audio.defaults.voice.preset = .broadcast }
        let raw = track.file.url(relativeTo: folder.url)
        #expect(try RenderInputs.load(folder).primaryAudio[source] == raw, "A render never plays a cleaning made with other settings.")
        #expect(try RenderInputs.load(folder, keepingEarlierCleaning: true).primaryAudio[source] == cleaned, "The preview keeps the last one meanwhile.")
    }

    @Test func theMixIsTheEditsLengthInMono() async throws {
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape)
        let mix = try await AudioMixRenderer.render(built)
        #expect(abs(Double(mix.count) / 48_000 - 2.2) < 0.01)
        #expect(mix.map(abs).max() ?? 0 > 0.05, "The tone plays.")
        #expect(abs(mix[0]) < 0.01, "Each clip fades in from silence.")
    }

    @Test func exportWritesAVideoOfEachShape() async throws {
        let url = folder.url(for: .exports).appending(path: "test.mp4")
        try await Exporter.export(try RenderInputs.load(folder), output: .vertical, to: url, mastering: { samples, _ in samples.map { $0 * 0.5 } })
        let asset = AVURLAsset(url: url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        #expect(size == CGSize(width: 1080, height: 1920))
        #expect(abs(try await asset.load(.duration).seconds - 2.2) < 0.05)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    @Test func srtFollowsTheCut() throws {
        let url = folder.url(for: .exports).appending(path: "test.srt")
        try Exporter.writeSRT(try RenderInputs.load(folder), to: url)
        let srt = try String(contentsOf: url, encoding: .utf8)
        #expect(srt.contains("Hello there."))
        #expect(srt.contains("00:00:00,950 --> ") == false, "Times are on the edited timeline, not the source.")
        let text = folder.url(for: .exports).appending(path: "test.txt")
        try Exporter.writeText(try RenderInputs.load(folder), to: text)
        #expect(try String(contentsOf: text, encoding: .utf8).hasPrefix("Hello there."))
    }
}

extension Transcript {
    /// The transcript as a draft again, to add to a project.
    var draft: TranscriptDraft {
        TranscriptDraft(
            engine: engine, silenceDetector: silenceDetector, language: language, audioDuration: audioDuration,
            items: items.map { item in
                switch item {
                case .word(let word): .word(.init(text: word.text, start: word.start, end: word.end, isFiller: word.isFiller))
                case .silence(let silence): .silence(start: silence.start, end: silence.end)
                }
            }
        )
    }
}

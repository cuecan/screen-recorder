import Foundation
import MCP
import Testing
import ProjectKit
import RenderKit
@testable import cuecan

/// A project in a temporary library, with one transcribed source and no media: enough for every tool that
/// edits by id.
private final class Workspace: Sendable {
    private let root: URL
    let library: ProjectLibrary
    let folder: ProjectFolder
    var context: ToolContext { ToolContext(library: library, author: .agent("Claude")) }
    var path: Value { .string(folder.url.path(percentEncoded: false)) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "cuecan-tools-\(UUID().uuidString)")
        library = ProjectLibrary(projectsFolder: root.appending(path: "Projects"), recentsFile: root.appending(path: "recents.json"))
        folder = try ProjectFolder.create(at: library.newProjectURL(title: "Tools test"), title: "Tools test")
        try folder.updateProject { project in
            project.addSource(
                name: "Camera",
                origin: .imported,
                tracks: [SourceTrack(kind: .video, file: .external(URL(filePath: "/tmp/none.mov")), media: MediaInfo(duration: 6, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1")))]
            )
        }
        var draft = TranscriptDraft(
            engine: "test", silenceDetector: "test", language: "en", audioDuration: 6,
            items: [
                .silence(start: 0, end: 1),
                .word(.init(text: "Hello", start: 1.0, end: 1.4)), .word(.init(text: "there.", start: 1.45, end: 1.8)),
                .silence(start: 1.8, end: 2.6),
                .word(.init(text: "Um,", start: 2.6, end: 2.9, isFiller: true)),
                .silence(start: 2.9, end: 3.0),
                .word(.init(text: "Q", start: 3.0, end: 3.3)), .word(.init(text: "can", start: 3.3, end: 3.6)),
                .silence(start: 3.6, end: 6),
            ]
        )
        draft.alternatives = [.init(words: 3..<5, text: "CueCan")]
        _ = try folder.addTranscript(draft, for: SourceID(number: 1))
    }

    deinit {
        // Keep temporary media, exports and test libraries out of the user's Projects window.
        try? FileManager.default.removeItem(at: root)
    }

    func call(_ name: String, _ arguments: [String: Value] = [:]) async -> CallTool.Result {
        var arguments = arguments
        if arguments["project"] == nil { arguments["project"] = path }
        return await MCPServer.call(name, arguments: arguments, context: context)
    }
}

private extension CallTool.Result {
    var text: String {
        content.compactMap { if case .text(let text, _, _) = $0 { text } else { nil } }.joined(separator: "\n")
    }
}

@Suite struct ToolTests {
    @Test func clipFramingKeepsTakeDefaultsSupportsLocalResetAndReportsOverrides() async throws {
        let workspace = try Workspace()
        try workspace.folder.updateProject { project in
            project.sources[0].tracks += [.screen, .camera].map { kind in
                SourceTrack(kind: kind, file: .inProject("recordings/\(kind.rawValue).mov"),
                            media: .init(duration: 6, video: .init(width: kind == .screen ? 1280 : 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "avc1")))
            }
            // A 32:27 screen: Side by side needs the room it was recorded with.
            project.sources[0].layout = .sideBySide(.thirtyTwoByTwentySeven)
        }
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        _ = await workspace.call("split_clip", ["time": 3])
        try workspace.folder.updateEdit(author: .system("Test"), reason: "Default camera framing") { edit in
            edit.setFraming(.init(centerX: 0.35, centerY: 0.45, zoom: 1.2), slot: .split, for: SourceID(number: 1))
        }
        let history = try workspace.folder.history.entries().count
        let zoom = await workspace.call("set_clip_framing", ["clip_ids": ["c_1", "c_2"], "picture": "camera", "zoom": 1.8])
        #expect(zoom.isError != true, "\(zoom.text)")
        let changed = try workspace.folder.loadEdit()
        #expect(changed.main.allSatisfy { $0.cameraTransform == PictureTransform(centerX: 0.35, centerY: 0.45, zoom: 1.8) })
        #expect(changed.framings(for: SourceID(number: 1)).framing(for: .split).zoom == 1.2)
        #expect(try workspace.folder.history.entries().count == history + 1)
        let screen = await workspace.call("set_clip_framing", ["clip_ids": ["c_1"], "picture": "screen", "center_x": 0.8, "zoom": 2])
        #expect(screen.isError != true, "\(screen.text)")
        let reset = await workspace.call("set_clip_framing", ["clip_ids": ["c_2"], "picture": "camera", "reset": true])
        #expect(reset.isError != true, "\(reset.text)")
        let final = try workspace.folder.loadEdit()
        #expect(final.main[0].cameraTransform?.zoom == 1.8)
        #expect(final.main[1].cameraTransform == nil)
        #expect(final.main[0].screenTransform == .init(centerX: 0.8, zoom: 2))
        let summary = await workspace.call("get_edit")
        #expect(summary.text.contains("\"screenTransform\""))
        #expect(summary.text.contains("\"cameraTransform\""))
    }

    @Test func invalidClipFramingRequestsDoNotWriteAnyPartOfAChange() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let before = try workspace.folder.loadEdit()
        let history = try workspace.folder.history.entries()
        for arguments: [String: Value] in [
            ["clip_ids": ["c_1"], "picture": "screen", "zoom": 2], // This source has no screen.
            ["clip_ids": ["c_1"], "picture": "camera", "zoom": 4],
            ["clip_ids": ["c_1"], "picture": "everything", "zoom": 2],
            ["clip_ids": [], "picture": "camera", "reset": true],
            ["clip_ids": ["c_1", "c_99"], "picture": "camera", "reset": true],
        ] {
            let result = await workspace.call("set_clip_framing", arguments)
            #expect(result.isError == true)
            #expect(try workspace.folder.loadEdit() == before)
            #expect(try workspace.folder.history.entries() == history)
        }
    }

    @Test func aCancelledWordFixCannotSaveAnUntimedFallback() async throws {
        let workspace = try Workspace()
        let before = try workspace.folder.loadEdit()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await workspace.call("set_word_text", ["start_id": "w_1", "text": "Hi"])
        }
        let result = await task.value
        #expect(result.isError == true)
        #expect(try workspace.folder.loadEdit() == before)
    }

    @Test func listProjectsFindsProjectsInTheFolder() async throws {
        let workspace = try Workspace()
        let result = await MCPServer.call("list_projects", arguments: [:], context: workspace.context)
        #expect(result.isError != true)
        #expect(result.text.contains("Tools test"))
        #expect(result.text.contains("\"transcribed\" : true"))
    }

    @Test func aCutShowsInTheTranscriptAndTheEdit() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "w_1", "end_word_id": "w_5"])
        let cut = await workspace.call("cut", ["start_id": "w_3"])
        #expect(cut.isError != true, "\(cut.text)")
        #expect(cut.text.contains("shorter"))

        let transcript = await workspace.call("get_transcript")
        #expect(transcript.text.contains("+ w_1"), "Played words are marked.")
        #expect(transcript.text.contains("  w_3 "), "The cut filler isn't.")
        #expect(transcript.text.contains("[filler]"))
        #expect(transcript.text.contains("SpeechAnalyzer heard “CueCan” for w_4…w_5"))

        let edit = await workspace.call("get_edit")
        #expect(edit.text.contains("\"reason\" : \"Cut w_3\""))
        #expect(edit.text.contains("\"role\" : \"agent\"") && edit.text.contains("\"name\" : \"Claude\""))
    }

    @Test func layoutsAreReadInTheEditsOwnShape() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "w_1", "end_word_id": "w_5"])
        let set = await workspace.call("set_layout", [
            "clip_id": "all",
            "layout": ["kind": "card", "position": "bottomRight", "size": "large", "shape": "square", "screen": "full", "roundness": 0.3],
        ])
        #expect(set.isError != true, "\(set.text)")
        #expect(try workspace.folder.loadEdit().main.first?.layout == .card(Card(position: .bottomRight, size: .large, shape: .square, screen: .full)))

        let bad = await workspace.call("set_layout", ["clip_id": "c_1", "layout": ["kind": "bubble", "size": "huge", "shape": "16:9"]])
        #expect(bad.isError == true)
    }

    @Test func mistakesComeBackInPlainWords() async throws {
        let workspace = try Workspace()
        let unknown = await workspace.call("cut", ["start_id": "w_99"])
        #expect(unknown.isError == true)
        #expect(unknown.text.contains("There's no w_99"))
        let badID = await workspace.call("cut", ["start_id": "word 3"])
        #expect(badID.text.contains("isn't a word or silence id"))
        let missing = await workspace.call("split_clip", ["clip_id": "c_1"])
        #expect(missing.text.contains("“before_word_id” is required"))
        let tool = await workspace.call("make_it_good")
        #expect(tool.text.contains("no tool called"))
    }

    @Test func undoPutsTheEditBack() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "w_1", "end_word_id": "w_5"])
        _ = await workspace.call("cut", ["start_id": "w_3"])
        let undo = await workspace.call("undo")
        #expect(undo.isError != true)
        #expect(try workspace.folder.loadEdit().main.count == 1)
        #expect(try workspace.folder.loadEdit().duration > 2)
    }

    @Test func clearingTheVocabularyClearsItsSpellings() async throws {
        let workspace = try Workspace()
        let source = SourceID(number: 1)
        try workspace.folder.updateProject { $0.vocabulary = ["CueCan"] }
        try workspace.folder.saveSpellings(VocabularySpellings(source: source, terms: ["CueCan"], spellings: [.init(words: ItemRange(first: .word(WordID(number: 4)), last: .word(WordID(number: 5))), text: "CueCan")]))
        #expect(await workspace.call("get_transcript").text.contains("spelled “CueCan”"))

        let cleared = await workspace.call("set_vocabulary", ["terms": .array([])])
        #expect(cleared.text.contains("Cleared"))
        #expect(try workspace.folder.loadSpellings(for: source) == nil)
        #expect(!(await workspace.call("get_transcript").text.contains("spelled “CueCan”")))
    }

    @Test func spellingsFromOldTermsDontApply() throws {
        let workspace = try Workspace()
        let source = SourceID(number: 1)
        try workspace.folder.updateProject { $0.vocabulary = ["CueCan"] }
        try workspace.folder.saveSpellings(VocabularySpellings(source: source, terms: ["CueCan"], spellings: []))
        try workspace.folder.updateProject { $0.vocabulary = ["Laravel"] }
        #expect(try workspace.folder.currentSpellings(for: source, terms: ["Laravel"]) == nil)
    }

    @Test func theCameraIsFramedByPointAndZoom() async throws {
        let workspace = try Workspace()
        // The workspace's only source is imported footage, with no camera to frame.
        let none = await workspace.call("set_camera_framing", ["zoom": 1.3])
        #expect(none.isError == true)
        #expect(none.text.contains("no source in this project has a camera"))

        try workspace.folder.updateProject { project in
            project.addSource(
                name: "Screen recording",
                origin: .recorded,
                tracks: [SourceTrack(kind: .camera, file: .inProject("recordings/take/camera.mov"), media: MediaInfo(duration: 6, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1")))]
            )
        }
        let framed = await workspace.call("set_camera_framing", ["center_x": 0.42, "center_y": 0.38, "zoom": 1.3])
        #expect(framed.isError != true, "\(framed.text)")
        #expect(framed.text.contains("card centred at 0.42, 0.38, zoom 1.30"))
        let everywhere = try workspace.folder.loadEdit().framings(for: SourceID(number: 2))
        for slot in CameraSlot.allCases {
            #expect(everywhere[slot] == CameraFraming(centerX: 0.42, centerY: 0.38, zoom: 1.3), "With no slot, every slot is framed.")
        }

        let closer = await workspace.call("set_camera_framing", ["slot": "split", "zoom_by": 1.5])
        #expect(closer.isError != true)
        let framings = try workspace.folder.loadEdit().framings(for: SourceID(number: 2))
        #expect(abs((framings[.split]?.zoom ?? 0) - 1.95) < 0.0001)
        #expect(framings[.card]?.zoom == 1.3, "One slot changes on its own.")
        let report = try #require(closer.text.split(separator: "\n").first { $0.hasPrefix("Framed the camera") })
        #expect(report.contains("split centred at"))
        #expect(!report.contains("card"), "Only the slot asked for is reported.")
        #expect(await workspace.call("set_camera_framing", ["slot": "aboveScreen", "zoom": 2]).isError == true, "No slot belongs to one shape.")

        let wrongSlot = await workspace.call("set_camera_framing", ["slot": "corner", "zoom": 1.2])
        #expect(wrongSlot.isError == true)
        #expect(wrongSlot.text.contains("card, split, fullScreen or all"))

        let tooFar = await workspace.call("set_camera_framing", ["zoom": 5])
        #expect(tooFar.isError == true)
        #expect(tooFar.text.contains("from 1 to 3"))
        let beforeInvalidZoom = try workspace.folder.loadEdit()
        for value in ["nan", "inf", "-inf"] {
            let invalid = await workspace.call("set_camera_framing", ["zoom_by": .string(value)])
            #expect(invalid.isError == true)
            #expect(invalid.text.contains("finite number"))
            #expect(try workspace.folder.loadEdit() == beforeInvalidZoom, "Invalid zoom must not create an edit or undo entry.")
        }
        let wrongSource = await workspace.call("set_camera_framing", ["source_id": "src_1", "zoom": 1.2])
        #expect(wrongSource.text.contains("has no camera to frame"))

        let reset = await workspace.call("set_camera_framing", ["reset": true])
        #expect(reset.isError != true)
        #expect(try workspace.folder.loadEdit().camera.isEmpty)
        // Framing is an edit, so it's undone like one.
        _ = await workspace.call("set_camera_framing", ["zoom": 2])
        _ = await workspace.call("undo")
        #expect(try workspace.folder.loadEdit().camera.isEmpty)
    }

    @Test func cutsAndSplitsTakeTimes() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let cut = await workspace.call("cut", ["start_time": 4.0, "end_time": 5.5])
        #expect(cut.isError != true, "\(cut.text)")
        #expect(cut.text.contains("1.50 s shorter"))
        let split = await workspace.call("split_clip", ["time": 2.0])
        #expect(split.isError != true, "\(split.text)")
        #expect(try workspace.folder.loadEdit().main.count == 3)
        let bySource = await workspace.call("cut", ["source_id": "src_1", "start_time": 0.0, "end_time": 0.5])
        #expect(bySource.text.contains("0.50 s shorter"))
        let kept = await workspace.call("keep", ["source_id": "src_1", "start_time": 4.0, "end_time": 5.5])
        #expect(kept.text.contains("1.50 s longer"), "\(kept.text)")
    }

    @Test func cutEdgesAreCheckedByTheirSound() async throws {
        let workspace = try Workspace()
        // A mic for the source, with levels measured from it: speech where the transcript has words, quiet
        // elsewhere, the detector's threshold at −50 dB.
        let mic = FileReference.external(URL(filePath: "/tmp/cuecan-tools-test-mic.wav"))
        try workspace.folder.updateProject { project in
            project.sources[0].tracks.append(SourceTrack(kind: .microphone, file: mic,
                                                         media: MediaInfo(duration: 6, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))))
        }
        let speech: [(TimeInterval, TimeInterval)] = [(1.0, 1.8), (2.6, 2.9), (3.0, 3.6)]
        let frames = (0..<600).map { frame -> Double in
            let time = (Double(frame) + 0.5) / 100
            return speech.contains { $0.0 <= time && time < $0.1 } ? -20 : -70
        }
        try workspace.folder.saveLevels(SourceLevels(source: SourceID(number: 1), original: mic, detector: "energy", threshold: -50,
                                                     minimumSound: 0.03, envelope: SoundEnvelope(levels: frames, frameDuration: 0.01)))
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])

        // By id, the cut lands in the pauses either side of the filler: nothing to say.
        let clean = await workspace.call("cut", ["start_id": "w_3"])
        #expect(clean.isError != true, "\(clean.text)")
        #expect(!clean.text.contains("May catch a word"), "\(clean.text)")
        #expect(!clean.text.contains("soundAtEdges"))

        // By time, from partway through "Hello" (sound 1.0–1.8 s): the clip before now ends inside it.
        let clipped = await workspace.call("cut", ["source_id": "src_1", "start_time": 1.2, "end_time": 2.0])
        #expect(clipped.text.contains("May catch a word"), "\(clipped.text)")
        #expect(clipped.text.contains("end, at 1.20 s on the timeline"), "\(clipped.text)")
        #expect(clipped.text.contains("30 dB over the silence level"))
        #expect(clipped.text.contains("started 0.20 s before the edge and runs on 0.60 s after it"))
        #expect(clipped.text.contains("nudge_cut the end to keep it whole, by +600 ms, or to leave it out, by -200 ms"), "\(clipped.text)")
        #expect(clipped.text.contains("\"soundAtEdges\""))

        let edit = await workspace.call("get_edit")
        #expect(edit.text.contains("\"nudgeToKeepIt\" : 600"), "\(edit.text)")
        #expect(edit.text.contains("May catch a word"))

        // Nudged out to where the sound stops, it's clean.
        let clip = try #require(try workspace.folder.loadEdit().main.first { abs($0.playedRange.end - 1.2) < 0.001 })
        let nudged = await workspace.call("nudge_cut", ["clip_id": .string(clip.id.description), "edge": "end", "milliseconds": 600])
        #expect(nudged.isError != true, "\(nudged.text)")
        #expect(!nudged.text.contains("May catch a word"), "\(nudged.text)")
        let after = await workspace.call("get_edit")
        #expect(!after.text.contains("soundAtEdges"))
    }

    @Test func speedFreezeLookAndWordsAreEdits() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let speed = await workspace.call("set_speed", ["clip_id": "c_1", "rate": 4])
        #expect(speed.text.contains("4×, muted"), "\(speed.text)")
        // Frames of the edit's 30 fps clock, as the editor steps them: at 4×, three frames back are 0.4 s of source.
        let before = try #require(try workspace.folder.loadEdit().main.first?.endNudge)
        let nudged = await workspace.call("nudge_cut", ["clip_id": "c_1", "edge": "end", "frames": -3])
        #expect(nudged.isError != true, "\(nudged.text)")
        let after = try #require(try workspace.folder.loadEdit().main.first?.endNudge)
        #expect(abs(after - before + 0.4) < 0.0001, "\(after - before)")
        #expect(await workspace.call("set_speed", ["clip_id": "c_1", "rate": 3]).isError == true)
        _ = await workspace.call("set_speed", ["clip_id": "c_1", "rate": 1])
        let freeze = await workspace.call("freeze_screen", ["start_time": 1, "end_time": 2])
        #expect(freeze.text.contains("f_2"), "\(freeze.text)")
        let look = await workspace.call("set_look", ["inset": "L", "rounded": false, "background": "#d9d9d9", "mirror": true])
        #expect(look.isError != true, "\(look.text)")
        let clipLook = await workspace.call("set_layout", ["clip_id": "c_1", "camera_side": "left"])
        #expect(clipLook.isError != true, "\(clipLook.text)")
        #expect(await workspace.call("set_layout", ["clip_id": "c_1", "camera_side": "sideways"]).isError == true)
        let words = await workspace.call("set_word_text", ["start_id": "w_4", "end_id": "w_5", "text": "CueCan"])
        #expect(words.text.contains("“CueCan”"))
        let edit = try workspace.folder.loadEdit()
        #expect(edit.freezes.count == 1)
        #expect(edit.look == EditLook(inset: .large, rounded: false, background: "#D9D9D9", mirror: true))
        #expect(edit.main[0].look == ClipLook(cameraSide: .flipped))
        #expect(await workspace.call("set_layout", ["clip_id": "c_1", "inset": "L"]).isError == true, "The inset is set_look's now.")
        // The take has no sound to time it against, so the fix is one word that cuts as a whole.
        #expect(edit.fixes.map(\.words.count) == [1])
        #expect(edit.fixes.first?.replaces == ItemRange(first: .word(WordID(number: 4)), last: .word(WordID(number: 5))))
        #expect(words.text.contains("cuts as one word"), "\(words.text)")
        let transcript = await workspace.call("get_transcript")
        #expect(transcript.text.contains("CueCan") && !transcript.text.contains("Q can"), "\(transcript.text)")
        let summary = await workspace.call("get_edit")
        #expect(summary.text.contains("\"holdsFrameAt\""))
        _ = await workspace.call("freeze_screen", ["remove": true, "freeze_id": "f_2"])
        #expect(try workspace.folder.loadEdit().freezes.isEmpty)
    }

    @Test func clipsSoundIsSetPerClip() async throws {
        // docs/decisions.md, 71: levels in dB and Mute, for one clip or several, and get_edit shows them.
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        _ = await workspace.call("split_clip", ["time": 2])
        let quieter = await workspace.call("set_clip_sound", ["clip_ids": ["c_1"], "voice_db": -6])
        #expect(quieter.text.contains("c_1: voice −6 dB, system audio 0 dB"), "\(quieter.text)")
        let both = await workspace.call("set_clip_sound", ["clip_ids": ["c_1", "c_2"], "system_audio_db": -60, "muted": true])
        #expect(both.isError != true, "\(both.text)")
        let edit = try workspace.folder.loadEdit()
        #expect(edit.main.map(\.voiceLevel) == [-6, 0])
        #expect(edit.main.map(\.systemAudioLevel) == [-60, -60])
        #expect(edit.main.map(\.isMuted) == [true, true])
        #expect(await workspace.call("set_clip_sound", ["clip_ids": ["c_1"]]).isError == true, "Nothing to change.")
        #expect(await workspace.call("set_clip_sound", ["clip_ids": ["c_9"], "muted": false]).isError == true)
        let summary = await workspace.call("get_edit")
        #expect(summary.text.contains("\"voiceDb\"") && summary.text.contains("\"systemAudioDb\""), "\(summary.text)")
    }

    @Test func overlaysGoOverWordsOrTime() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let picture = workspace.folder.url.appending(path: "shot.png")
        try Data([0x89]).write(to: picture)
        let placed = await workspace.call("place_broll", ["file": .string(picture.path(percentEncoded: false)), "start_time": 1, "end_time": 2, "placement": "in_screens_place"])
        #expect(placed.isError != true, "\(placed.text)")
        let overlay = try #require(try workspace.folder.loadEdit().overlays.first)
        #expect(overlay.isStill && overlay.placement == .inScreensPlace)
        _ = await workspace.call("place_broll", ["overlay_id": .string(overlay.id.description), "start_word_id": "w_1", "end_word_id": "w_2"])
        #expect(try workspace.folder.loadEdit().overlays.first?.over == .words(ItemRange(first: .word(WordID(number: 1)), last: .word(WordID(number: 2)))))
        _ = await workspace.call("place_broll", ["overlay_id": .string(overlay.id.description), "remove": true])
        #expect(try workspace.folder.loadEdit().overlays.isEmpty)
    }

    @Test func theEditorStateSaysWhereTheCreatorIs() async throws {
        let workspace = try Workspace()
        #expect(await workspace.call("get_editor_state").text.contains("hasn't been open"))
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let revision = try workspace.folder.loadEdit().revision
        try workspace.folder.saveEditorState(EditorState(playhead: 1.2, selection: .init(clips: [ClipID(number: 1)]), markIn: 1, markOut: 1.9, editRevision: revision))
        let state = await workspace.call("get_editor_state")
        #expect(state.text.contains("1.20 s on the timeline, in c_1"), "\(state.text)")
        #expect(state.text.contains("inside w_1 “Hello”"))
        #expect(state.text.contains("Marked range: 1.00–1.90 s"))
        #expect(state.text.contains("w_1…w_2"))
    }

    @Test func theScreenTimelineAndTextCanBeSearched() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let analysis = ScreenAnalysis(
            source: SourceID(number: 1), sampleRate: 4, readText: true,
            changes: [.init(start: 1, end: 2)],
            stills: [.init(start: 2, end: 4, text: [.init(text: "export OPENAI_KEY=sk-test", box: [0.1, 0.1, 0.5, 0.05], confidence: 0.9)])]
        )
        try workspace.folder.saveScreenAnalysis(analysis)
        let found = await workspace.call("find_on_screen", ["text": "openai_key"])
        #expect(found.text.contains("2.00 s · src_1 2.00–4.00 s"), "\(found.text)")
        let timeline = await workspace.call("get_screen_timeline", ["start_time": 0, "end_time": 5])
        #expect(timeline.text.contains("changing until 2.00"), "\(timeline.text)")
        #expect(timeline.text.contains("still until 4.00 · text: “export OPENAI_KEY=sk-test”"))
        #expect(await workspace.call("find_on_screen", ["text": "nowhere"]).text.contains("wasn't seen"))
    }

    @Test func rejectedRequestsLeaveTheEditAndHistoryUntouched() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let before = try workspace.folder.loadEdit()
        let history = try workspace.folder.history.entries()
        let requests: [(String, [String: Value])] = [
            ("cut", ["start_id": "w_1", "start_time": 1, "end_time": 2]),
            ("keep", ["source_id": "src_1", "start_id": "w_1"]),
            ("split_clip", ["time": 1, "before_word_id": "w_1"]),
            ("place_broll", ["source_id": "src_1", "file": "/tmp/missing.png", "start_time": 1, "end_time": 2]),
            ("nudge_cut", ["clip_id": "c_1", "edge": "start", "frames": 2, "milliseconds": 10]),
        ]
        for (tool, arguments) in requests {
            let result = await workspace.call(tool, arguments)
            #expect(result.isError == true, "\(tool) must reject the request")
            #expect(try workspace.folder.loadEdit() == before)
            #expect(try workspace.folder.history.entries() == history)
        }
    }

    @Test func helperUsesCapturedCleanupSettingsAndPreservesWarnings() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let folder = workspace.folder
        try folder.updateProject { project in
            project.sources[0].tracks.append(SourceTrack(kind: .microphone, file: .inProject("recordings/missing.wav"),
                media: MediaInfo(duration: 6, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))))
        }
        try folder.updateEdit(author: .system("Test"), reason: "No cleanup") { $0.audio.defaults.cleanup.mode = .off }
        let plan = ExportPlan(inputs: try RenderInputs.load(folder), destination: folder.url(for: .exports),
                              kind: .handoff(splitAtSilences: false))
        try folder.updateEdit(author: .system("Test"), reason: "Cleanup changed after export began") { $0.audio.defaults.cleanup.mode = .natural }
        let snapshot = folder.url.appending(path: "export-plan.json")
        try plan.write(to: snapshot)
        let command = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/debug/cuecan")
        let output = try await CommandRunner.run(executable: command, arguments: ["--machine", "export_plan", snapshot.path])
        guard case .exported(let captured) = try HelperMessage.result(in: output) else { Issue.record("Expected exported result"); return }
        #expect(captured.warnings.isEmpty, "The captured off setting must not try to read the missing mic.")
        #expect(captured.files.count == 3)
        let liveSnapshot = folder.url.appending(path: "current-export-plan.json")
        try ExportPlan(inputs: RenderInputs.load(folder), destination: folder.url(for: .exports),
                       kind: .handoff(splitAtSilences: false)).write(to: liveSnapshot)
        // Exercise the helper's structured warnings without registering a temporary fixture in the
        // real user's recent list. export_timeline itself is covered below with an isolated context.
        let live = try await CommandRunner.run(executable: command, arguments: ["--machine", "export_plan", liveSnapshot.path])
        guard case .exported(let result) = try HelperMessage.result(in: live) else { Issue.record("Expected exported result"); return }
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].contains("missing.wav"))
        #expect(result.files.count == 3)
        let failed = try await CommandRunner.run(executable: command, arguments: ["--machine", "export_plan", folder.url.appending(path: "missing-plan.json").path])
        #expect(failed.status != 0)
        #expect(throws: HelperMessage.Failure.self) { try HelperMessage.result(in: failed) }
    }

    @Test func exportTimelineWritesFCPXMLAndTheTranscript() async throws {
        let workspace = try Workspace()
        _ = await workspace.call("add_clip", ["start_word_id": "s_1", "end_word_id": "s_4"])
        let result = await workspace.call("export_timeline", ["split_at_silences": true])
        #expect(result.isError != true, "\(result.text)")
        let exports = workspace.folder.url(for: .exports)
        let xml = try String(contentsOf: exports.appending(path: "Tools test.fcpxml"), encoding: .utf8)
        #expect(xml.contains("<fcpxml version=\"1.10\">"))
        #expect(xml.contains("value=\"Silence\""))
        #expect(try XMLDocument(xmlString: xml, options: []).rootElement()?.name == "fcpxml")
        #expect(FileManager.default.fileExists(atPath: exports.appending(path: "Tools test.srt").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: exports.appending(path: "Tools test.txt").path(percentEncoded: false)))
    }
}

@Suite struct CommandLineTests {
    @Test func flagsReadAsJSONWhereTheyCan() throws {
        let values = try CuecanCommand.parse(["--project", "/tmp/a b", "--position", "2", "--at_cuts", "--times", "[1, 2.5]"])
        #expect(values["project"] == .string("/tmp/a b"))
        #expect(values["position"] == .int(2))
        #expect(values["at_cuts"] == .bool(true))
        #expect(values["times"] == .array([.int(1), .double(2.5)]))
    }

    @Test func oneJSONObjectIsTheArguments() throws {
        #expect(try CuecanCommand.parse([#"{"project": "x", "start_id": "w_1"}"#]) == ["project": "x", "start_id": "w_1"])
        #expect(throws: ToolError.self) { try CuecanCommand.parse(["{oops"]) }
    }

    @Test func everyToolHasASchemaThatNamesItsRequiredArguments() {
        for tool in ToolCatalog.all {
            guard case .object(let schema) = tool.inputSchema, case .object(let properties)? = schema["properties"] else {
                Issue.record("\(tool.name) has no properties")
                continue
            }
            for case .string(let name) in schema["required"]?.arrayValue ?? [] {
                #expect(properties[name] != nil, "\(tool.name) requires \(name) but doesn't describe it.")
            }
        }
        #expect(Set(ToolCatalog.all.map(\.name)).count == ToolCatalog.all.count)
    }
}

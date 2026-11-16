import AppKit
import Foundation
import ProjectKit
import SwiftUI
import Testing
@testable import CueCan

@MainActor
struct InspectorInteractionTests {
    @Test func cardControlsEditTheCardShownWhenSideBySideHasNoRoom() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.updateProject { project in
            project.format = VideoFormat(destination: .landscape, layout: .card(.standard))
            project.sources[0].layout = .card(.standard)
            project.sources[0].tracks[0] = .init(kind: .screen, file: .inProject("recordings/screen.mov"),
                media: .init(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 60, captureRate: 60, codec: "hvc1")))
        }
        let id = ClipID(number: 1)
        try folder.updateEdit(author: .app, reason: "Unavailable layout fixture") { try $0.setLayout(.sideBySide, for: id) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(selecting: id)
        let before = try folder.loadEdit()
        let history = try folder.history.entries().count
        model.changeCards("Move displayed card", for: [id]) { $0.position = .topLeft }
        let after = try folder.loadEdit()
        #expect(after.main[0].layout == .card(Card(position: .topLeft)))
        #expect(after.main[1] == before.main[1])
        #expect(after.camera == before.camera)
        #expect(try folder.history.entries().count == history + 1)
    }

    @Test func choosingTheSharedCardButtonPreservesDifferentCardsWithoutAnUndoStep() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let first = Card(position: .left, size: .small, shape: .square, screen: .full, roundness: 0.25)
        let second = Card(position: .bottomRight, size: .large, shape: .wide, screen: .smaller, roundness: 0.18)
        try folder.updateEdit(author: .app, reason: "Mixed cards fixture") { edit in
            try edit.setLayout(.card(first), for: ClipID(number: 1))
            try edit.setLayout(.card(second), for: ClipID(number: 2))
        }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        let before = try folder.loadEdit()
        let history = try folder.history.entries()
        #expect(LayoutChoice.shared(in: before.main.map(\.layout)) == .card)
        model.setLayout(.card, for: [ClipID(number: 1), ClipID(number: 2)])
        #expect(try folder.loadEdit() == before)
        #expect(try folder.history.entries() == history)
    }

    @Test func choosingCardForMixedLayoutsKeepsAnExistingCardAndInitializesOnlyTheOtherClip() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let own = Card(position: .topLeft, size: .large, shape: .square, roundness: 0.4)
        try folder.updateEdit(author: .app, reason: "Mixed layouts fixture") { edit in
            try edit.setLayout(.card(own), for: ClipID(number: 1))
            try edit.setLayout(.camera, for: ClipID(number: 2))
        }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        let before = try folder.loadEdit()
        let history = try folder.history.entries().count
        model.setLayout(.card, for: [ClipID(number: 1), ClipID(number: 2)])
        let after = try folder.loadEdit()
        #expect(after.main[0] == before.main[0])
        #expect(after.main[1].layout == .card(.standard))
        #expect(after.main[1].cameraTransform == before.main[1].cameraTransform)
        #expect(after.main[1].screenTransform == before.main[1].screenTransform)
        #expect(try folder.history.entries().count == history + 1)
        try folder.undo()
        #expect(try folder.loadEdit().main == before.main)
    }

    @Test func escapeDismissesThePanelBeforeClearingTheClipAndOldDismissalsCannotCloseANewPanel() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(selecting: ClipID(number: 1))
        let selection = model.selection
        model.inspectorPopover = .equalizer
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(EditorKeys.handle(escape, model: model))
        #expect(model.inspectorPopover == nil)
        #expect(model.selection == selection)
        #expect(EditorKeys.handle(escape, model: model))
        #expect(model.selection.isEmpty)
        let audio = model.presentation(of: .equalizer), layout = model.presentation(of: .layout)
        audio.wrappedValue = true
        layout.wrappedValue = true
        audio.wrappedValue = false
        #expect(model.inspectorPopover == .layout)
        model.inspectorTab = .audio
        #expect(model.inspectorPopover == nil)
    }

    @Test func choosingTheCurrentAudioAmountDoesNotStartProcessingOrWriteHistory() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        let processing = ProcessingCenter()
        let before = try folder.loadEdit()
        let history = try folder.history.entries()
        let amount = before.audio.settings(for: SourceID(number: 1)).cleanup.amount
        model.setVoice(for: SourceID(number: 1), "Cleanup \(amount)%", processing: processing) { $0.cleanup.amount = amount }
        #expect(processing.activity.isEmpty)
        #expect(processing.problems.isEmpty)
        #expect(try folder.loadEdit() == before)
        #expect(try folder.history.entries() == history)
    }

    @Test func consecutiveGesturesPreserveCommittedParametersBeforeThePreviewReloads() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(selecting: ClipID(number: 1))
        let count = try folder.history.entries().count
        model.setTransform(picture: .camera, zoom: 1.8)
        model.setTransform(picture: .camera, centerX: 0.7)
        model.setTransform(picture: .camera, zoom: 1.2)
        let committed = try folder.loadEdit()
        #expect(committed.main[0].cameraTransform == PictureTransform(centerX: 0.7, centerY: 0.4, zoom: 1.2))
        #expect(try folder.history.entries().count == count + 3)
        try folder.undo()
        #expect(try folder.loadEdit().main[0].cameraTransform == PictureTransform(centerX: 0.7, centerY: 0.4, zoom: 1.8))
    }

    @Test func layoutSectionResetRestoresItsParametersWithoutResettingOtherSections() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let id = ClipID(number: 2)
        try folder.updateEdit(author: .app, reason: "QA changed layout") { edit in
            try edit.setLayout(.camera, for: id)
            try edit.changeLook(for: id) { $0.cameraSide = .flipped; $0.captions = true }
            edit.look.inset = .large
        }
        let before = try folder.loadEdit()
        let count = try folder.history.entries().count
        let model = EditorModel(folder: folder)
        model.loadForPreview(selecting: id)
        model.resetClipLayout(for: [id])
        let after = try folder.loadEdit()
        #expect(after.main[0] == before.main[0])
        #expect(after.main[1].layout == .automatic)
        #expect(after.look.inset == .large, "The inset is the project's: a clip's reset leaves it.")
        #expect(after.main[1].look.cameraSide == .standard)
        #expect(after.main[1].look.captions)
        #expect(after.main[1].cameraTransform == before.main[1].cameraTransform)
        #expect(after.main[1].screenTransform == before.main[1].screenTransform)
        #expect(after.main[1].voiceLevel == before.main[1].voiceLevel)
        #expect(try folder.history.entries().count == count + 1)
        try folder.undo()
        #expect(try folder.loadEdit().main == before.main)
    }

    @Test func changingOneMixedFramingParameterPreservesTheOthersAndUndoesOnce() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        model.selection = .clips([ClipID(number: 1), ClipID(number: 2)])
        let before = try folder.loadEdit()
        let history = try folder.history.entries().count
        #expect(model.sharedClipValue(\.voiceLevel) == nil)
        #expect(model.sharedClipValue(\.look.cameraSide) == .standard)
        model.setTransform(picture: .camera, centerX: 0.75)
        let after = try folder.loadEdit()
        #expect(after.main[0].cameraTransform == PictureTransform(centerX: 0.75, centerY: 0.4, zoom: 1.2))
        #expect(after.main[1].cameraTransform == PictureTransform(centerX: 0.75, centerY: 0.6, zoom: 2))
        #expect(after.main[0].screenTransform == before.main[0].screenTransform)
        #expect(after.main[1].screenTransform == before.main[1].screenTransform)
        #expect(after.camera == before.camera, "A clip adjustment must not change the take's defaults.")
        #expect(try folder.history.entries().count == history + 1)
        try folder.undo()
        #expect(try folder.loadEdit().main == before.main)
    }

    @Test func cameraResetFollowsTheTakeAndScreenResetCannotChangeIt() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        model.selection = .clips([ClipID(number: 2)])
        model.resetTransform(picture: .camera)
        model.loadForPreview(selecting: ClipID(number: 2))
        let clip = try #require(model.selectedClip)
        #expect(clip.cameraTransform == nil)
        #expect(model.transform(of: clip, picture: .camera) == PictureTransform(centerX: 0.35, centerY: 0.4, zoom: 1.2))
        model.resetTransform(picture: .screen)
        #expect(try folder.loadEdit().main[1].screenTransform == nil)
        #expect(try folder.loadEdit().main[1].cameraTransform == nil)
    }

    @Test func transcriptAndProjectNavigationKeepTheInspectedScopeExplicit() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        model.inspectorTab = .transcript
        model.selectClip(ClipID(number: 1))
        #expect(model.inspectorTab == .video)
        model.inspectorTab = .audio
        model.selectClip(ClipID(number: 2))
        #expect(model.inspectorTab == .audio, "Changing clips preserves the kind of setting being inspected.")
        model.inspectProject()
        #expect(model.selection.isEmpty)
        #expect(model.inspectorTab == .video)
    }

    @Test func settingTheExistingValueDoesNotWriteAnUndoStep() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(selecting: ClipID(number: 1))
        let before = try folder.loadEdit()
        let history = try folder.history.entries()
        model.setTransform(picture: .camera, zoom: 1.2)
        #expect(try folder.loadEdit() == before)
        #expect(try folder.history.entries() == history)
    }

    private func fixture() throws -> ProjectFolder {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-inspector-tests-\(UUID())"), title: "Inspector fixture")
        let project = try folder.updateProject { project in
            project.addSource(name: "Fixture take", origin: .recorded, tracks: [
                .init(kind: .screen, file: .inProject("recordings/screen.mov"), media: .init(duration: 10, video: .init(width: 1280, height: 1080, frameRate: 60, captureRate: 60, codec: "hvc1"))),
                .init(kind: .camera, file: .inProject("recordings/camera.mov"), media: .init(duration: 10, video: .init(width: 1920, height: 1080, frameRate: 30, captureRate: 30, codec: "hvc1"))),
            ], layout: .sideBySide(.thirtyTwoByTwentySeven))
        }
        let source = try #require(project.sources.first)
        try folder.updateEdit(author: .system("Test"), reason: "Fixture") { edit in
            edit.main = [
                Clip(id: ClipID(number: 1), source: source.id, sourceIn: 0, sourceOut: 5, voiceLevel: -6),
                Clip(id: ClipID(number: 2), source: source.id, sourceIn: 5, sourceOut: 10, voiceLevel: -12,
                     screenTransform: .init(zoom: 1.5), cameraTransform: .init(centerX: 0.6, centerY: 0.6, zoom: 2)),
            ]
            edit.setFraming(.init(centerX: 0.35, centerY: 0.4, zoom: 1.2), slot: .split, for: source.id)
        }
        return folder
    }
}

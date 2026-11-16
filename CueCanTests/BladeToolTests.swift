import AppKit
import Foundation
import ProjectKit
import Testing
@testable import CueCan

/// The blade is for one cut unless it's kept on.
@MainActor
struct BladeToolTests {
    private func makeModel() throws -> (EditorModel, ProjectFolder) {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-blade-\(UUID())"), title: "Blade")
        return (EditorModel(folder: folder), folder)
    }

    @Test func theBladeGoesBackToSelectAfterOneCutUnlessItsKeptOn() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        model.pickBlade()
        #expect(model.tool == .blade && !model.keepsBlade)
        model.bladeDidCut()
        #expect(model.tool == .select)
        // Picked again while it's on, it's kept on, and stays through cuts.
        model.pickBlade()
        model.pickBlade()
        #expect(model.tool == .blade && model.keepsBlade)
        model.bladeDidCut()
        model.bladeDidCut()
        #expect(model.tool == .blade && model.keepsBlade)
        // Once more, it's for one cut again.
        model.pickBlade()
        #expect(model.tool == .blade && !model.keepsBlade)
    }

    @Test func anotherToolOrEscapeLetsGoOfAKeptBlade() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        model.pickBlade()
        model.pickBlade()
        model.tool = .trim
        #expect(!model.keepsBlade)
        model.pickBlade()
        #expect(model.tool == .blade && !model.keepsBlade, "It doesn't come back kept on.")
        model.pickBlade()
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(EditorKeys.handle(escape, model: model))
        #expect(model.tool == .select && !model.keepsBlade)
        // A cut made any other way, such as ⌘B, leaves the tool alone.
        model.tool = .trim
        model.bladeDidCut()
        #expect(model.tool == .trim)
    }
}

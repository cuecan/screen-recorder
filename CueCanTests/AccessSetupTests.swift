import Foundation
import RecorderKit
import Testing
@testable import CueCan

/// The first-run setup window's model (docs/ui.md, board 11), with macOS stood in for.
@MainActor
struct AccessSetupTests {
    /// What macOS would report, and what was asked of it.
    final class System {
        var statuses: [AccessKind: AccessStatus] = [:]
        var prompts: [AccessKind] = []
        var opened: [AccessKind] = []
    }

    private func makeDefaults() -> UserDefaults {
        let name = "cuecan-access-setup-\(UUID())"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeModel(_ system: System, defaults: UserDefaults, onPrompt: @escaping (AccessKind) -> Void = { _ in }) -> AccessSetupModel {
        AccessSetupModel(defaults: defaults, read: { system.statuses[$0] ?? .undecided },
                         ask: { kind in system.prompts.append(kind); onPrompt(kind) },
                         openSettings: { system.opened.append($0) })
    }

    @Test func allowingTheCameraAsksMacOSAndShowsItsAnswer() async throws {
        let system = System()
        let model = makeModel(system, defaults: makeDefaults()) { system.statuses[$0] = .allowed }
        model.press(.camera)
        #expect(model.asking == [.camera])
        model.press(.camera)
        try await waitUntil { model.asking.isEmpty }
        #expect(system.prompts == [.camera], "A second press while the prompt is up asks nothing.")
        #expect(model.list.state(of: .camera) == .allowed)
        #expect(system.opened.isEmpty)
    }

    @Test func screenRecordingIsAskedForOnceThenOpensSystemSettingsAndIsRememberedAcrossALaunch() async throws {
        let system = System(), defaults = makeDefaults()
        let model = makeModel(system, defaults: defaults)
        model.press(.screenRecording)
        try await waitUntil { model.asking.isEmpty }
        #expect(system.prompts == [.screenRecording])
        #expect(model.list.state(of: .screenRecording) == .waiting)
        model.press(.screenRecording)
        #expect(system.opened == [.screenRecording] && system.prompts == [.screenRecording])

        // macOS reopens CueCan once the switch is on: a new model reads what was asked, and the new answer.
        let stillOff = makeModel(system, defaults: defaults)
        #expect(stillOff.list.state(of: .screenRecording) == .waiting)
        #expect(stillOff.list.state(of: .accessibility) == .ask)
        system.statuses[.screenRecording] = .allowed
        let reopened = makeModel(system, defaults: defaults)
        #expect(reopened.list.state(of: .screenRecording) == .allowed)
    }

    @Test func aSwitchTurnedOnInSystemSettingsIsSeenOnTheNextLook() {
        let system = System()
        system.statuses = [.camera: .denied]
        let model = makeModel(system, defaults: makeDefaults())
        #expect(model.list.state(of: .camera) == .waiting)
        model.press(.camera)
        #expect(system.opened == [.camera] && system.prompts.isEmpty)
        system.statuses[.camera] = .allowed
        model.refresh()
        #expect(model.list.state(of: .camera) == .allowed)
    }

    @Test func onlyFinishingStopsTheWindowOpeningAtLaunch() {
        let defaults = makeDefaults()
        let model = makeModel(System(), defaults: defaults)
        model.press(.accessibility)
        #expect(!defaults.bool(forKey: AccessSetupModel.doneKey))
        model.finish()
        #expect(defaults.bool(forKey: AccessSetupModel.doneKey))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
}

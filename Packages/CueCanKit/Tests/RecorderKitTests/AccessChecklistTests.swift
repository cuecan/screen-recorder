import AVFoundation
import Testing
@testable import RecorderKit

/// The first-run access list (docs/ui.md, board 11): what each row shows and what its button does.
struct AccessChecklistTests {
    @Test func aNewInstallOffersToAskForEachKind() {
        let list = AccessChecklist()
        for kind in AccessKind.allCases { #expect(list.state(of: kind) == .ask) }
        #expect(!list.canRecord && !list.isComplete)
        #expect(list.missing == [.camera, .microphone, .screenRecording, .accessibility])
    }

    @Test(arguments: [AccessKind.camera, .microphone])
    func cameraAndMicrophoneWaitForTheirPromptWithoutPointingAtSystemSettings(kind: AccessKind) {
        var list = AccessChecklist()
        do { let result = list.press(kind); #expect(result == .prompt(kind)) }
        #expect(list.state(of: kind) == .ask, "macOS's own prompt is up; the row must not say to go to System Settings.")
        #expect(list.asked.isEmpty)
        do { let result = list.update(kind, to: .allowed); #expect(result) }
        #expect(list.state(of: kind) == .allowed)
        do { let result = list.press(kind); #expect(result == nil) }
    }

    @Test(arguments: [AccessKind.camera, .microphone])
    func aRefusedPromptLeadsToSystemSettings(kind: AccessKind) {
        var list = AccessChecklist()
        _ = list.press(kind)
        do { let result = list.update(kind, to: .denied); #expect(!result) }
        #expect(list.state(of: kind) == .waiting)
        do { let result = list.press(kind); #expect(result == .openSettings(kind)) }
        do { let result = list.update(kind, to: .allowed); #expect(result, "Turning the switch on in System Settings is seen.") }
        #expect(list.state(of: kind) == .allowed)
    }

    @Test(arguments: [AccessKind.screenRecording, .accessibility])
    func aSwitchInSystemSettingsIsAskedForOnceThenWaitedFor(kind: AccessKind) {
        var list = AccessChecklist()
        do { let result = list.press(kind); #expect(result == .prompt(kind)) }
        #expect(list.state(of: kind) == .waiting)
        #expect(list.asked == [kind])
        // macOS shows its prompt once, so the button now opens System Settings itself.
        do { let result = list.press(kind); #expect(result == .openSettings(kind)) }
        do { let result = list.update(kind, to: .undecided); #expect(!result) }
        #expect(list.state(of: kind) == .waiting)
        do { let result = list.update(kind, to: .allowed); #expect(result) }
        do { let result = list.update(kind, to: .allowed); #expect(!result, "Only the change is reported.") }
        #expect(list.state(of: kind) == .allowed)
    }

    @Test func whatWasAskedBeforeIsStillWaitedForAfterCueCanIsReopened() {
        // macOS can quit CueCan when Screen Recording is switched on: the list comes back where it was.
        var reopened = AccessChecklist(asked: [.screenRecording])
        #expect(reopened.state(of: .screenRecording) == .waiting)
        #expect(reopened.state(of: .accessibility) == .ask)
        reopened.update(.screenRecording, to: .allowed)
        #expect(reopened.state(of: .screenRecording) == .allowed)
    }

    @Test func accessTakenAwayAgainIsAskedForAgain() {
        var list = AccessChecklist()
        list.update(.camera, to: .allowed)
        list.update(.camera, to: .denied)
        #expect(list.state(of: .camera) == .waiting)
        do { let result = list.update(.camera, to: .allowed); #expect(result) }
    }

    @Test func recordingNeedsEverythingButAccessibility() {
        var list = AccessChecklist()
        list.update(.camera, to: .allowed)
        list.update(.microphone, to: .allowed)
        #expect(!list.canRecord)
        list.update(.screenRecording, to: .allowed)
        #expect(list.canRecord && !list.isComplete)
        #expect(list.missing == [.accessibility])
        list.update(.accessibility, to: .allowed)
        #expect(list.isComplete)
    }

    @Test func onlyAccessibilityIsOptional() {
        #expect(AccessKind.allCases.filter(\.isOptional) == [.accessibility])
        #expect(AccessKind.allCases.filter(\.isAnsweredInThePrompt) == [.camera, .microphone])
    }

    @Test func macOSsCaptureAnswersMapToTheListsStatuses() {
        #expect(SystemAccess.status(of: AVAuthorizationStatus.authorized) == .allowed)
        #expect(SystemAccess.status(of: AVAuthorizationStatus.notDetermined) == .undecided)
        #expect(SystemAccess.status(of: AVAuthorizationStatus.denied) == .denied)
        #expect(SystemAccess.status(of: AVAuthorizationStatus.restricted) == .denied)
    }
}

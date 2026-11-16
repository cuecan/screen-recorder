import Testing
@testable import RecorderKit

struct SetupHandoverTests {
    @Test func fastStartsStillShowTheRecordingPanelAndRetireTheSetupAfterTheAnimation() {
        var handover = SetupHandover()
        let id = handover.begin()
        #expect(handover.accepts(id, phase: .recording))
        #expect(handover.accepts(id, phase: .paused))
        #expect(!handover.canRetireAfterRecordingStarted)
        let finished1 = handover.animationFinished(id, phase: .recording)
        #expect(finished1)
        #expect(handover.canRetireAfterRecordingStarted)
    }

    @Test func aStartKeepsTheSetupForAStartupFailureUntilRecordingBegins() {
        var handover = SetupHandover()
        let id = handover.begin()
        let finished2 = handover.animationFinished(id, phase: .starting)
        #expect(!finished2)
        #expect(handover.canRetireAfterRecordingStarted)
        handover.cancel()
        #expect(!handover.isLeaving)
        #expect(!handover.accepts(id, phase: .settingUp))
        let finished3 = handover.animationFinished(id, phase: .recording)
        #expect(!finished3)
    }

    @Test func anOldAnimationCannotHideAReplacementSetup() {
        var handover = SetupHandover()
        let old = handover.begin()
        handover.cancel()
        let current = handover.begin()
        let finished4 = handover.animationFinished(old, phase: .starting)
        #expect(!finished4)
        #expect(handover.accepts(current, phase: .starting))
        for phase in [RecordingPhase.idle, .settingUp, .saving, .discarding] {
            #expect(!handover.accepts(current, phase: phase))
        }
    }
}

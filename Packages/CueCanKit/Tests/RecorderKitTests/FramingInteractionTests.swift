import CoreGraphics
import Testing
import ProjectKit
@testable import RecorderKit

@Suite struct FramingInteractionTests {
    @Test func draggingUsesThePictureCoordinatesAndMirroring() throws {
        let size = CGSize(width: 400, height: 300)
        let origin = CGPoint(x: 200, y: 150)
        let point = CGPoint(x: 240, y: 180)
        #expect(FramingDrag.idle.framing(at: point, in: size) == nil)
        for mirrored in [false, true] {
            let drag = FramingDrag.dragging(origin: origin, framing: .centered.zoomed(to: 2), mirrored: mirrored)
            let framing = try #require(drag.framing(at: point, in: size))
            #expect(abs(framing.centerX - (mirrored ? 0.4 : 0.6)) < 0.00001)
            #expect(abs(framing.centerY - 0.4) < 0.00001)
            #expect(framing.zoom == 2)
            #expect(drag.framing(at: point, in: .zero) == nil)
            #expect(drag.framing(at: origin, in: size) == .centered.zoomed(to: 2))
        }
    }

    @Test func startingAndSavingAreNeitherReadyNorRecording() {
        #expect(RecordingPhase.starting.statusTitle == "Starting")
        #expect(RecordingPhase.saving.statusTitle == "Saving…")
        #expect(RecordingPhase.discarding.statusTitle == "Discarding…")
        for phase in RecordingPhase.allCases {
            #expect(phase.showsElapsed == (phase == .recording || phase == .paused))
            #expect(phase.allowsPanelHandOver == (phase == .starting || phase == .recording || phase == .paused),
                    "The hand-over must still run when a take starts before its 200 ms animation delay.")
        }
    }

    @Test func onlyThePartOfAWindowAfterTheHoldExpiresFalls() {
        var meter = LevelBallistics(fallRate: 20, holdDuration: 0.15)
        meter.observe([LevelSample(peak: 1, rms: 0)])
        meter.observe([.silence], windowDuration: 0.1)
        #expect(meter.peakDecibels == 0)
        meter.observe([.silence], windowDuration: 0.1)
        #expect(abs(meter.peakDecibels - -1) < 0.00001)
        meter.observe([.silence], windowDuration: 0.1)
        #expect(abs(meter.peakDecibels - -3) < 0.00001)
        meter.observe([LevelSample(peak: 1, rms: 0)])
        meter.observe([.silence], windowDuration: 0.1)
        #expect(meter.peakDecibels == 0, "A louder peak starts a fresh hold.")
    }
}

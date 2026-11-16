import Foundation
import Testing
@testable import RecorderKit

@Suite struct ReviewRegressionTests {
    @Test func aGapInTheMicIsFilledWithSilence() {
        var placement = SamplePlacement(sampleRate: 48_000)
        #expect(placement.place(count: 1024, at: 0.5) == (0, 0))
        #expect(placement.place(count: 1024, at: 0.5 + 1024 / 48_000) == (0, 0), "Back to back.")
        // The mic was unplugged for 5 seconds, then came back.
        let back = placement.place(count: 1024, at: 5.5)
        #expect(back.silence == 48_000 * 5 - 2048)
        #expect(placement.written == 48_000 * 5 + 1024, "Sample n plays at n ÷ rate after the first.")
    }

    @Test func jitterIsLeftAloneAndOverlapIsDropped() {
        var placement = SamplePlacement(sampleRate: 48_000)
        _ = placement.place(count: 1000, at: 0)
        #expect(placement.place(count: 1000, at: 1000.0 / 48_000 + 0.002) == (0, 0), "2 ms early or late is jitter.")
        let overlap = placement.place(count: 1000, at: 0.02)
        #expect(overlap == (0, 1000), "Wholly inside what's written.")
    }

    @Test func theTimerHoldsStillWhilePaused() {
        var pauses = PauseTimeline()
        pauses.pause(at: 5)
        #expect(pauses.elapsed(at: 10) == 5)
        pauses.resume(at: 12)
        #expect(pauses.elapsed(at: 13) == 6)

        let clock = RecordingClock()
        clock.start(at: 100)
        clock.pause(at: 105)
        #expect(clock.elapsed(at: 110) == 5)
        clock.resume(at: 111)
        #expect(clock.elapsed(at: 112) == 6, "No jump back on Resume.")
    }

    @Test func theMeterRisesAtOnceAndFallsSlowly() {
        var meter = LevelBallistics()
        meter.observe([LevelSample(peak: 1, rms: 0.5)])
        #expect(meter.decibels == 0)
        // Then silence: 20 dB a second, so 0.1 s later it's at −2 dB, not gone.
        meter.observe([LevelSample](repeating: .silence, count: 5))
        #expect(abs(meter.decibels - -2) < 0.001)
        meter.observe([LevelSample(peak: 0.1, rms: 0)])
        #expect(abs(meter.decibels - -2.4) < 0.001, "A quieter window doesn't pull it down faster.")
    }

    @Test func thePeakIsHeldThenFalls() {
        var meter = LevelBallistics(holdDuration: 1)
        meter.observe([LevelSample(peak: 1, rms: 0.5)])
        #expect(meter.peakDecibels == 0)
        // 0.9 s of silence: the level falls, the held peak stays.
        meter.observe([LevelSample](repeating: .silence, count: 45))
        #expect(meter.peakDecibels == 0)
        #expect(meter.decibels < -17)
        // Past the hold, it falls, but never below the level itself.
        meter.observe([LevelSample](repeating: .silence, count: 15))
        #expect(meter.peakDecibels < 0)
        #expect(meter.peakDecibels >= meter.decibels)
        // A peak louder than the falling one is held at once.
        meter.observe([LevelSample](repeating: .silence, count: 200))
        meter.observe([LevelSample(peak: 0.5, rms: 0)])
        #expect(meter.peakDecibels == LevelSample(peak: 0.5, rms: 0).peakDecibels)
        meter.reset()
        #expect(meter.peakDecibels == -120)
    }
}

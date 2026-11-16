import Foundation
import ProjectKit
import Testing
@testable import AudioKit

@Suite struct AudioSamplesTests {
    @Test func slicingClampsToTheAudio() {
        let audio = AudioSamples(samples: (0..<100).map(Float.init), sampleRate: 100)
        #expect(audio.duration == 1)
        #expect(audio.slice(TimeRange(start: 0.1, end: 0.2)).samples == (10..<20).map(Float.init))
        #expect(audio.slice(TimeRange(start: -1, end: 0.05)).samples == (0..<5).map(Float.init))
        #expect(audio.slice(TimeRange(start: 0.95, end: 3)).samples == (95..<100).map(Float.init))
        #expect(audio.slice(TimeRange(start: 0.5, end: 0.4)).samples.isEmpty)
    }

    @Test func gainIsInDecibels() {
        let audio = AudioSamples(samples: [0.5, -0.25], sampleRate: 10)
        let louder = audio.applyingGain(decibels: 20 * log10(2))
        #expect(abs(louder.samples[0] - 1.0) < 1e-6)
        #expect(abs(louder.samples[1] - -0.5) < 1e-6)
    }

    @Test(arguments: [16_000.0, 24_000.0, 44_100.0])
    func resamplingKeepsDurationAndLevel(target: Double) throws {
        let audio = AudioSamples(samples: Signal.sine(frequency: 440, peakDecibels: -6, duration: 2), sampleRate: 48_000)
        let resampled = try audio.resampled(to: target)
        #expect(resampled.sampleRate == target)
        #expect(abs(resampled.duration - 2) < 0.01)
        let before = LoudnessMeter.integratedLoudness(of: audio)
        let after = LoudnessMeter.integratedLoudness(of: resampled)
        #expect(abs(before - after) < 0.1)
    }

    @Test func resamplingToTheSameRateIsANoOp() throws {
        let audio = AudioSamples(samples: [0.1, 0.2], sampleRate: 48_000)
        #expect(try audio.resampled(to: 48_000) == audio)
    }

    @Test func splicingJoinsStretchesInOrder() {
        let audio = AudioSamples(samples: [Float](repeating: 1, count: 1_000), sampleRate: 1_000)
        let spliced = AudioSplicer.splice(
            audio,
            ranges: [TimeRange(start: 0.5, end: 0.6), TimeRange(start: 0.1, end: 0.3)],
            fade: 0.01
        )
        #expect(spliced.samples.count == 300)
        // Each stretch fades in from 0 and out to near 0, and is at full level in between.
        #expect(spliced.samples[0] == 0)
        #expect(spliced.samples[50] == 1)
        #expect(spliced.samples[99] < 0.2)
        #expect(spliced.samples[100] == 0)
        #expect(spliced.samples[200] == 1)
    }

    @Test func splicingCanLeaveGaps() {
        let audio = AudioSamples(samples: [Float](repeating: 1, count: 1_000), sampleRate: 1_000)
        let spliced = AudioSplicer.splice(
            audio,
            ranges: [TimeRange(start: 0, end: 0.1), TimeRange(start: 0.2, end: 0.3)],
            fade: 0,
            gap: 0.05
        )
        #expect(spliced.samples.count == 250)
        #expect(spliced.samples[99] == 1)
        #expect(spliced.samples[100..<150].allSatisfy { $0 == 0 })
        #expect(spliced.samples[150] == 1)
    }

    @Test func fadesNeverOverlapOnAShortPiece() {
        let audio = AudioSamples(samples: [Float](repeating: 1, count: 10), sampleRate: 1_000)
        let spliced = AudioSplicer.splice(audio, ranges: [TimeRange(start: 0, end: 0.01)], fade: 1)
        #expect(spliced.samples.count == 10)
        #expect(spliced.samples.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}

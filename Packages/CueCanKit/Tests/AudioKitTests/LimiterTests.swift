import Foundation
import Testing
@testable import AudioKit

@Suite struct TruePeakLimiterTests {
    /// A voice-like test signal: a steady tone with short, loud transients, peaking well over full scale.
    func spiky(peak: Double = 6) -> AudioSamples {
        var samples = Signal.sine(frequency: 220, peakDecibels: peak - 14, duration: 4)
        let spike = Float(pow(10, peak / 20)) - 0.2
        for start in stride(from: 9_000, to: samples.count - 200, by: 13_000) {
            for offset in 0..<96 { samples[start + offset] += spike * Float(sin(Double(offset) / 96 * .pi)) }
        }
        return AudioSamples(samples: samples, sampleRate: 48_000)
    }

    @Test func truePeaksStayUnderTheCeiling() {
        let input = spiky()
        #expect(TruePeakMeter.truePeak(of: input) > 4)
        let output = TruePeakLimiter(ceiling: -1).process(input)
        #expect(output.truePeak <= -0.99)
        #expect(abs(TruePeakMeter.truePeak(of: output.audio) - output.truePeak) < 1e-9)
        #expect(output.maximumReduction > 5)
    }

    @Test func peaksBetweenSamplesAreCaughtToo() {
        // Every sample sits at ±0.85, under the ceiling, but the waveform between them reaches 1.2.
        let samples = (0..<48_000).map { index -> Float in
            let envelope = min(1, Double(min(index, 47_999 - index)) / 480)
            return Float(1.2 * envelope * sin(Double.pi / 2 * Double(index) + Double.pi / 4))
        }
        let audio = AudioSamples(samples: samples, sampleRate: 48_000)
        #expect(audio.peak < 0.89)
        #expect(TruePeakLimiter(ceiling: -1).process(audio).truePeak <= -0.99)
    }

    @Test func audioUnderTheCeilingIsUntouched() {
        let input = AudioSamples(samples: Signal.sine(frequency: 440, peakDecibels: -6, duration: 1), sampleRate: 48_000)
        let output = TruePeakLimiter(ceiling: -1).process(input)
        #expect(output.audio == input)
        #expect(output.maximumReduction == 0)
    }

    @Test func theGainIsDownBeforeThePeakArrives() {
        // A loud burst after silence: thanks to the look-ahead, its very first cycle is already under.
        let burst = AudioSamples(samples: Signal.silence(duration: 0.5) + Signal.sine(frequency: 1_000, peakDecibels: 6, duration: 0.5), sampleRate: 48_000)
        let output = TruePeakLimiter(ceiling: -1).process(burst)
        let onset = AudioSamples(samples: Array(output.audio.samples[24_000..<24_048]), sampleRate: 48_000)
        #expect(20 * log10(Double(onset.peak)) <= -0.99)
    }
}

@Suite struct LoudnessStageTests {
    @Test func landsOnTheTargetUnderTheCeiling() {
        // Quiet, with high peaks for its loudness, like a raw voice recording.
        var samples = Signal.sine(frequency: 220, peakDecibels: -30, duration: 6)
        for start in stride(from: 7_000, to: samples.count - 200, by: 11_000) {
            for offset in 0..<120 { samples[start + offset] += 0.2 * Float(sin(Double(offset) / 120 * .pi)) }
        }
        let output = LoudnessStage.process(AudioSamples(samples: samples, sampleRate: 48_000), target: -14, ceiling: -1)
        #expect(abs(output.loudness - -14) <= 0.1)
        #expect(output.truePeak <= -0.99)
        #expect(output.limiterReduction > 3, "Getting there needs the limiter.")
        #expect(output.gain > 14)
    }

    /// Peaks far above the loudness, so reaching the target takes heavy limiting, where loudness no longer
    /// rises dB for dB with gain.
    @Test func landsOnTheTargetUnderHeavyLimiting() {
        var samples = Signal.sine(frequency: 220, peakDecibels: -40, duration: 6)
        for start in stride(from: 2_000, to: samples.count - 300, by: 2_500) {
            for offset in 0..<240 { samples[start + offset] += 0.3 * Float(sin(Double(offset) / 240 * .pi)) }
        }
        let output = LoudnessStage.process(AudioSamples(samples: samples, sampleRate: 48_000), target: -14, ceiling: -1)
        #expect(output.limiterReduction > 8)
        #expect(abs(output.loudness - -14) <= 0.1)
        #expect(output.truePeak <= -0.99)
    }

    @Test func silenceIsLeftAlone() {
        let silence = AudioSamples(samples: Signal.silence(duration: 1), sampleRate: 48_000)
        let output = LoudnessStage.process(silence)
        #expect(output.audio == silence)
        #expect(output.gain == 0)
    }
}

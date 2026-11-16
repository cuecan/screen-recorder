import Foundation
import Testing
@testable import AudioKit

@Suite struct TruePeakTests {
    /// A sine at a quarter of the sample rate, phased so every sample lands at ±0.707: its sample peak is
    /// −3 dBFS, but its true peak is 0 dBTP.
    @Test func peaksBetweenSamplesAreFound() {
        // Faded in and out over 10 ms, since a full-scale sine that starts abruptly really does overshoot.
        let count = 48_000
        let fade = 480
        let samples = (0..<count).map { index -> Float in
            let envelope = min(1, Double(min(index, count - 1 - index)) / Double(fade))
            return Float(envelope * sin(Double.pi / 2 * Double(index) + Double.pi / 4))
        }
        let audio = AudioSamples(samples: samples, sampleRate: 48_000)
        #expect(abs(20 * log10(Double(audio.peak)) - -3.01) < 0.01)
        #expect(abs(TruePeakMeter.truePeak(of: audio)) < 0.1)
    }

    @Test(arguments: [44_100.0, 48_000.0, 96_000.0])
    func aLowToneReadsItsAmplitude(sampleRate: Double) {
        let audio = AudioSamples(samples: Signal.sine(frequency: 997, peakDecibels: -6, duration: 1, sampleRate: sampleRate), sampleRate: sampleRate)
        #expect(abs(TruePeakMeter.truePeak(of: audio) - -6) < 0.05)
    }

    @Test func truePeakIsNeverBelowTheSamplePeak() {
        var samples = Signal.silence(duration: 0.1)
        samples[100] = 0.5
        samples[101] = 0.5
        let audio = AudioSamples(samples: samples, sampleRate: 48_000)
        #expect(TruePeakMeter.linearTruePeak(of: audio) >= audio.peak)
    }

    @Test func silenceHasNoPeak() {
        #expect(TruePeakMeter.truePeak(of: AudioSamples(samples: Signal.silence(duration: 0.1), sampleRate: 48_000)) == -.infinity)
        #expect(TruePeakMeter.truePeak(of: AudioSamples(samples: [], sampleRate: 48_000)) == -.infinity)
    }

    @Test func eachPhaseFilterHasUnityGain() {
        for phase in TruePeakMeter.phaseFilters(factor: 4) {
            #expect(abs(phase.reduce(0, +) - 1) < 1e-5)
        }
    }
}

@Suite struct SignalAlignmentTests {
    /// Deterministic noise, standing in for a voice's waveform.
    func noise(count: Int, seed: UInt64) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53) * 2 - 1) * 0.3
        }
    }

    /// A cleaned version as a model makes it: the voice without the original's noise, scaled, and delayed
    /// by `lag` samples. Returns the original too, which is the voice plus noise.
    func versions(lag: Int, scale: Float) -> (original: AudioSamples, processed: AudioSamples) {
        let count = 48_000 * 4
        let voice = noise(count: count, seed: 7)
        let roomNoise = noise(count: count, seed: 99)
        let original = zip(voice, roomNoise).map { $0 + $1 * 0.2 }
        let processed = (0..<count).map { index -> Float in
            let source = index - lag
            return source >= 0 && source < count ? voice[source] * scale : 0
        }
        return (AudioSamples(samples: original, sampleRate: 48_000), AudioSamples(samples: processed, sampleRate: 48_000))
    }

    @Test(arguments: [0, 1, 37, 480, -120, -1])
    func findsTheOffsetToTheSample(lag: Int) {
        let (original, processed) = versions(lag: lag, scale: 0.5)
        let alignment = SignalAlignment.measure(original: original, processed: processed)
        #expect(alignment.lag == lag)
        #expect(alignment.correlation > 0.8)
        #expect(abs(alignment.gain - 2) < 0.05, "The gain undoes the processed version's 0.5 scale.")
    }

    /// A rebuilt voice: the same syllables, so the same loudness envelope, but a new waveform. The waveform
    /// can't line it up, so the envelopes do, to the millisecond, and the gain matches loudness.
    @Test func aRebuiltVoiceIsLinedUpByItsEnvelope() {
        let count = 48_000 * 4
        // Syllables and gaps of irregular lengths, from 60 to 400 ms, like speech. Regular ones would
        // repeat within the search range and fit at more than one lag.
        var envelope = [Float](repeating: 0.02, count: count)
        var state: UInt64 = 5
        var position = 0
        var loud = true
        while position < count {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let length = 2_880 + Int(state >> 33) % 16_320
            if loud { for index in position..<min(count, position + length) { envelope[index] = 1 } }
            position += length
            loud.toggle()
        }
        func syllables(_ index: Int) -> Float { envelope[index] }
        let carrierA = noise(count: count, seed: 11)
        let carrierB = noise(count: count, seed: 12)
        let lag = 2_400
        let original = (0..<count).map { carrierA[$0] * syllables($0) }
        let rebuilt = (0..<count).map { index -> Float in
            let source = index - lag
            return source >= 0 ? carrierB[index] * syllables(source) * 0.25 : 0
        }
        let alignment = SignalAlignment.measure(
            original: AudioSamples(samples: original, sampleRate: 48_000),
            processed: AudioSamples(samples: rebuilt, sampleRate: 48_000)
        )
        #expect(alignment.method == .envelope)
        #expect(alignment.correlation < SignalAlignment.waveformThreshold)
        #expect(abs(alignment.lag - lag) <= 48)
        #expect(abs(alignment.gain - 4) < 0.3, "The gain undoes the 0.25 scale by loudness.")
    }

    @Test func aCleanedVoiceIsLinedUpByItsWaveform() {
        let (original, processed) = versions(lag: 37, scale: 0.5)
        #expect(SignalAlignment.measure(original: original, processed: processed).method == .waveform)
    }

    @Test func unrelatedAudioHasLowCorrelation() {
        let original = AudioSamples(samples: noise(count: 48_000 * 2, seed: 1), sampleRate: 48_000)
        let other = AudioSamples(samples: noise(count: 48_000 * 2, seed: 2), sampleRate: 48_000)
        #expect(SignalAlignment.measure(original: original, processed: other).correlation < 0.1)
    }

    @Test func applyingTheAlignmentLinesTheVersionsUp() {
        let voice = noise(count: 48_000, seed: 3)
        let delayed = AudioSamples(samples: [Float](repeating: 0, count: 25) + voice.map { $0 * 0.5 }, sampleRate: 48_000)
        let alignment = SignalAlignment(lag: 25, correlation: 1, gain: 2)
        let aligned = alignment.apply(to: delayed, length: voice.count)
        #expect(aligned.samples.count == voice.count)
        let largestError = zip(aligned.samples, voice).map { abs($0 - $1) }.max() ?? 1
        #expect(largestError < 1e-5)
    }

    @Test func blendsRunFromOriginalToCleaned() {
        let original = AudioSamples(samples: [1, 1, 1], sampleRate: 48_000)
        let cleaned = AudioSamples(samples: [0, 0, 0], sampleRate: 48_000)
        #expect(SignalAlignment.blend(original: original, aligned: cleaned, amount: 0).samples == [1, 1, 1])
        #expect(SignalAlignment.blend(original: original, aligned: cleaned, amount: 100).samples == [0, 0, 0])
        #expect(SignalAlignment.blend(original: original, aligned: cleaned, amount: 25).samples == [0.75, 0.75, 0.75])
    }

    @Test func tooShortToMeasureIsNoOffset() {
        let tiny = AudioSamples(samples: [0.1, 0.2], sampleRate: 48_000)
        #expect(SignalAlignment.measure(original: tiny, processed: tiny) == SignalAlignment(lag: 0, correlation: 0, gain: 1))
    }
}

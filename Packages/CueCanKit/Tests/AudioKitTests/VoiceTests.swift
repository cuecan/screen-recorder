import Foundation
import Testing
@testable import AudioKit

@Suite struct BiquadTests {
    @Test func highPassCutsRumbleAndKeepsTheVoice() {
        let filter = Biquad.highPass(frequency: 80, sampleRate: 48_000)
        #expect(filter.gain(at: 20, sampleRate: 48_000) < -20)
        #expect(abs(filter.gain(at: 80, sampleRate: 48_000) - -3.01) < 0.05)
        #expect(abs(filter.gain(at: 1_000, sampleRate: 48_000)) < 0.1)
    }

    @Test(arguments: [4.0, -3.0])
    func peakingMovesItsBandByItsGain(gain: Double) {
        let filter = Biquad.peaking(frequency: 4_000, gain: gain, q: 0.8, sampleRate: 48_000)
        #expect(abs(filter.gain(at: 4_000, sampleRate: 48_000) - gain) < 0.01)
        #expect(abs(filter.gain(at: 100, sampleRate: 48_000)) < 0.1)
    }

    @Test func zeroGainIsNoFilter() {
        #expect(Biquad.peaking(frequency: 4_000, gain: 0, q: 1, sampleRate: 48_000) == .identity)
        let samples: [Float] = [0.1, -0.2, 0.3]
        #expect(Biquad.identity.apply(samples) == samples)
    }

    @Test func filteringATonePassesItAtTheFiltersGain() {
        let filter = Biquad.peaking(frequency: 1_000, gain: 6, q: 1, sampleRate: 48_000)
        let tone = AudioSamples(samples: Signal.sine(frequency: 1_000, peakDecibels: -20, duration: 2), sampleRate: 48_000)
        let filtered = AudioSamples(samples: filter.apply(tone.samples), sampleRate: 48_000)
        let change = LoudnessMeter.integratedLoudness(of: filtered) - LoudnessMeter.integratedLoudness(of: tone)
        #expect(abs(change - 6) < 0.1)
    }
}

@Suite struct CompressorTests {
    /// The peak level in dBFS of the last second.
    func tailPeak(_ samples: [Float], sampleRate: Double = 48_000) -> Double {
        20 * log10(Double(samples.suffix(Int(sampleRate)).map { abs($0) }.max() ?? 0))
    }

    /// The RMS level in dBFS of the last second.
    func tailLevel(_ samples: [Float], sampleRate: Double = 48_000) -> Double {
        let tail = samples.suffix(Int(sampleRate))
        let meanSquare = tail.reduce(0) { $0 + Double($1) * Double($1) } / Double(tail.count)
        return 10 * log10(meanSquare)
    }

    func tone(peak level: Double, frequency: Double = 1_000, duration: TimeInterval = 3) -> [Float] {
        Signal.sine(frequency: frequency, peakDecibels: level, duration: duration)
    }

    @Test func aboveTheThresholdEveryRatioDecibelsOfPeakGiveOne() {
        let compressor = Compressor(threshold: -30, ratio: 4, attack: 0.003, release: 0.1)
        // A peak 20 dB over the threshold at 4:1 comes out 5 dB over it.
        #expect(abs(tailPeak(compressor.apply(tone(peak: -10), sampleRate: 48_000)) - -25) < 0.3)
    }

    @Test func belowTheThresholdNothingChanges() {
        let compressor = Compressor(threshold: -10, ratio: 4, attack: 0.003, release: 0.1)
        let input = tone(peak: -30)
        #expect(compressor.apply(input, sampleRate: 48_000) == input)
    }

    @Test func makeUpGainIsAddedAfter() {
        let compressor = Compressor(threshold: -30, ratio: 2, attack: 0.003, release: 0.1, makeUpGain: 3)
        // 10 dB over at 2:1 is 5 dB over, plus 3 dB.
        #expect(abs(tailPeak(compressor.apply(tone(peak: -20), sampleRate: 48_000)) - -22) < 0.3)
    }

    @Test func theLargestReductionIsCapped() {
        let compressor = Compressor(threshold: -40, ratio: 10, attack: 0.003, release: 0.1, maximumReduction: 6)
        #expect(abs(tailPeak(compressor.apply(tone(peak: -10), sampleRate: 48_000)) - -16) < 0.3)
    }

    /// A short, loud transient on a steady voice, like a plosive. Reacting to peaks, the compressor turns the
    /// transient down far more than the voice, so the peak comes down against the loudness.
    @Test func shortTransientsComeDown() {
        var samples = tone(peak: -20, frequency: 200, duration: 4)
        for start in stride(from: 12_000, to: samples.count - 200, by: 12_000) {
            for offset in 0..<144 { samples[start + offset] += Float(0.6 * sin(Double(offset) / 144 * .pi)) }
        }
        let audio = AudioSamples(samples: samples, sampleRate: 48_000)
        let compressor = Compressor(threshold: -18, ratio: 4, attack: 0.001, release: 0.1, lookahead: 0.001)
        let output = AudioSamples(samples: compressor.apply(samples, sampleRate: 48_000), sampleRate: 48_000)
        func peakToLoudness(_ audio: AudioSamples) -> Double {
            TruePeakMeter.truePeak(of: audio) - LoudnessMeter.integratedLoudness(of: audio)
        }
        // The transient comes most of the way down the static curve: it peaks about 15 dB over the
        // threshold, so 4:1 allows about 11 dB.
        #expect(TruePeakMeter.truePeak(of: audio) - TruePeakMeter.truePeak(of: output) > 8)
        // The gap between peak and loudness narrows, by less than the transient's drop, because the
        // release keeps the voice down for a moment after each one.
        #expect(peakToLoudness(output) < peakToLoudness(audio) - 4)
    }

    /// With look-ahead, the gain is already down when a loud burst starts, so less of its onset gets through.
    @Test func lookaheadCatchesTheOnset() {
        let burst = Signal.silence(duration: 0.5) + tone(peak: -3, duration: 0.5)
        let threshold = -30.0
        func onsetPeak(lookahead: TimeInterval) -> Double {
            let compressor = Compressor(threshold: threshold, ratio: 10, attack: 0.005, release: 0.1, lookahead: lookahead)
            let output = compressor.apply(burst, sampleRate: 48_000)
            let onset = output[24_000..<(24_000 + 480)]
            return 20 * log10(Double(onset.map { abs($0) }.max() ?? 0))
        }
        #expect(onsetPeak(lookahead: 0.005) < onsetPeak(lookahead: 0) - 3)
    }

    @Test func reductionIsReported() {
        let compressor = Compressor(threshold: -30, ratio: 4, attack: 0.003, release: 0.1)
        let output = compressor.process(tone(peak: -10), sampleRate: 48_000)
        let report = GainReduction(output.reduction)
        #expect(abs(report.maximum - 15) < 0.5)
        #expect(report.shareOfTime > 0.95)
        #expect(abs(report.averageWhileWorking - 15) < 1)
    }

    @Test func aSplitBandCompressorLeavesTheRestAlone() {
        let deEsser = Compressor(threshold: -40, ratio: 4, attack: 0.001, release: 0.05, maximumReduction: 8, bandHighPass: 6_000)
        let low = tone(peak: -12, frequency: 300)
        #expect(abs(tailLevel(deEsser.apply(low, sampleRate: 48_000)) - tailLevel(low)) < 0.1)

        // Far over the threshold, the band is turned down by the cap. The zero-phase split passes the
        // filter's gain squared, so the tone drops by 1 − (1 − g)·|H|².
        let sibilance = tone(peak: -12, frequency: 12_000)
        let bandGain = pow(10, 2 * Biquad.highPass(frequency: 6_000, sampleRate: 48_000).gain(at: 12_000, sampleRate: 48_000) / 20)
        let expected = 20 * log10(1 - (1 - pow(10, -8.0 / 20)) * bandGain)
        let change = tailLevel(deEsser.apply(sibilance, sampleRate: 48_000)) - tailLevel(sibilance)
        #expect(abs(change - expected) < 0.3)
    }

    @Test func aSplitBandCompressorBelowItsThresholdPassesTheInputExactly() {
        let deEsser = Compressor(threshold: 0, ratio: 4, attack: 0.001, release: 0.05, bandHighPass: 6_000)
        let input = tone(peak: -30, frequency: 8_000)
        let output = deEsser.apply(input, sampleRate: 48_000)
        let largestError = zip(input, output).map { abs($0 - $1) }.max() ?? 1
        #expect(largestError < 1e-6)
    }

    @Test func staticCurve() {
        let compressor = Compressor(threshold: -20, ratio: 3, attack: 0, release: 0)
        #expect(compressor.staticReduction(atLevel: -30) == 0)
        #expect(abs(compressor.staticReduction(atLevel: -5) - 10) < 1e-9)
    }
}

@Suite struct SpeechPeaksTests {
    @Test func thresholdIsAPercentileOfSpeechPeaks() throws {
        // Three seconds peaking at −20 dBFS and one at −8: the louder quarter of the speech.
        let samples = Signal.sine(frequency: 500, peakDecibels: -20, duration: 3) + Signal.sine(frequency: 500, peakDecibels: -8, duration: 1)
        let median = try #require(SpeechPeaks.threshold(samples, sampleRate: 48_000, percentile: 50))
        #expect(abs(median - -20) < 0.1)
        let top = try #require(SpeechPeaks.threshold(samples, sampleRate: 48_000, percentile: 90))
        #expect(abs(top - -8) < 0.1)
    }

    @Test func pausesDontCount() throws {
        // Half the time is near-silence, which would drag a percentile down if it counted.
        let samples = Signal.sine(frequency: 500, peakDecibels: -70, duration: 2) + Signal.sine(frequency: 500, peakDecibels: -15, duration: 2)
        let low = try #require(SpeechPeaks.threshold(samples, sampleRate: 48_000, percentile: 10))
        #expect(abs(low - -15) < 0.1)
    }

    @Test func silenceHasNoThreshold() {
        #expect(SpeechPeaks.threshold([], sampleRate: 48_000, percentile: 50) == nil)
    }
}

@Suite struct VoicePresetTests {
    @Test func zeroIsNothing() {
        let scaled = VoicePreset.broadcast.scaled(to: 0)
        #expect(scaled.highPass == nil)
        #expect(scaled.eq.allSatisfy { $0.gain == 0 })
        #expect(scaled.compression.ratio == 1)
        #expect(scaled.compression.makeUpGain == 0)
        #expect(scaled.deEsser?.maximumReduction == 0)
    }

    @Test func fullIsThePreset() {
        #expect(VoicePreset.broadcast.scaled(to: 100) == .broadcast)
        #expect(VoicePreset.clear.scaled(to: 100) == .clear)
    }

    /// Decision 34: at 50% the EQ moves are half as big, the ratio moves toward 1:1 with make-up gain
    /// following, and the threshold stays.
    @Test func halfwayFollowsDecision34() {
        let preset = VoicePreset.broadcast
        let half = preset.scaled(to: 50)
        #expect(half.eq.map(\.gain) == preset.eq.map { $0.gain / 2 })
        #expect(half.eq.map(\.frequency) == preset.eq.map(\.frequency))
        #expect(half.compression.ratio == 1 + (preset.compression.ratio - 1) / 2)
        #expect(half.compression.thresholdPercentile == preset.compression.thresholdPercentile)
        #expect(half.compression.lookahead == preset.compression.lookahead)
        let expectedMakeUp = preset.compression.makeUpGain * (1 - 1 / half.compression.ratio) / (1 - 1 / preset.compression.ratio)
        #expect(abs(half.compression.makeUpGain - expectedMakeUp) < 1e-12)
        #expect(half.highPass == preset.highPass)
    }

    @Test func processingAtZeroChangesNothing() {
        let audio = AudioSamples(samples: Signal.sine(frequency: 200, peakDecibels: -12, duration: 1), sampleRate: 48_000)
        #expect(VoiceProcessor.process(audio, preset: .broadcast, amount: 0) == audio)
    }

    @Test func processingEvensOutLevelJumps() {
        // Talking at one level, then leaning in for a second: the preset narrows the jump.
        let steady = Signal.sine(frequency: 500, peakDecibels: -17, duration: 3)
        let leaningIn = Signal.sine(frequency: 500, peakDecibels: -7, duration: 1)
        let audio = AudioSamples(samples: steady + leaningIn, sampleRate: 48_000)
        let output = VoiceProcessor.process(audio, preset: .broadcast, amount: 100)
        #expect(output.samples.count == audio.samples.count)
        func level(_ samples: ArraySlice<Float>) -> Double {
            10 * log10(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        }
        let jumpBefore = level(audio.samples[(48_000 * 3 + 9_600)...]) - level(audio.samples[48_000..<96_000])
        let jumpAfter = level(output.samples[(48_000 * 3 + 9_600)...]) - level(output.samples[48_000..<96_000])
        #expect(jumpAfter < jumpBefore - 3)
    }

    @Test func runningReportsTheReduction() throws {
        let steady = Signal.sine(frequency: 500, peakDecibels: -17, duration: 3)
        let leaningIn = Signal.sine(frequency: 500, peakDecibels: -7, duration: 1)
        let result = VoiceProcessor.run(AudioSamples(samples: steady + leaningIn, sampleRate: 48_000), preset: .broadcast, amount: 100)
        let compression = try #require(result.compression)
        // 10 dB over a threshold at the steady level, at 4:1, is about 7.5 dB down.
        #expect(abs(compression.maximum - 7.5) < 1)
        #expect(VoiceProcessor.run(AudioSamples(samples: steady, sampleRate: 48_000), preset: .clear, amount: 0).compression == nil)
    }

    @Test func presetsSitInThePublishedRanges() {
        for preset in [VoicePreset.clear, .broadcast] {
            #expect((3...5).contains(preset.compression.ratio))
            #expect((0.001...0.005).contains(preset.compression.attack))
            #expect((0.1...0.2).contains(preset.compression.release))
            #expect(preset.highPass == 80)
            #expect(preset.eq.allSatisfy { abs($0.gain) <= 3 })
        }
        // Broadcast lifts warmth rather than cutting the low mids.
        #expect(VoicePreset.broadcast.eq.contains { (150...300).contains($0.frequency) && $0.gain > 0 })
        #expect(!VoicePreset.broadcast.eq.contains { $0.frequency < 500 && $0.gain < 0 })
    }

    @Test func stagesCanBeHeardOnTheirOwn() {
        let audio = AudioSamples(
            samples: Signal.sine(frequency: 200, peakDecibels: -20, duration: 3) + Signal.sine(frequency: 200, peakDecibels: -6, duration: 1),
            sampleRate: 48_000
        )
        let eqOnly = VoiceProcessor.run(audio, preset: .broadcast, amount: 100, stages: .eq)
        #expect(eqOnly.compression == nil)
        // The warmth lift raises a 200 Hz tone.
        #expect(LoudnessMeter.integratedLoudness(of: eqOnly.audio) > LoudnessMeter.integratedLoudness(of: audio) + 1)
        let dynamicsOnly = VoiceProcessor.run(audio, preset: .broadcast, amount: 100, stages: .dynamics)
        #expect(dynamicsOnly.compression != nil)
    }

    @Test func presetsComeFromTheSettings() {
        #expect(VoicePreset.preset(.off) == nil)
        #expect(VoicePreset.preset(.clear) == .clear)
        #expect(VoicePreset.preset(.broadcast) == .broadcast)
    }
}

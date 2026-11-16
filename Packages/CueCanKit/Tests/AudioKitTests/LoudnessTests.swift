import Foundation
import Testing
@testable import AudioKit

@Suite struct LoudnessTests {
    /// BS.1770-4, Tables 1 and 2: the K-weighting coefficients at 48 kHz.
    @Test func kWeightingMatchesTheStandardAt48kHz() {
        let filter = KWeightingFilter(sampleRate: 48_000)
        let tolerance = 1e-8
        #expect(abs(filter.shelf.b0 - 1.53512485958697) < tolerance)
        #expect(abs(filter.shelf.b1 - -2.69169618940638) < tolerance)
        #expect(abs(filter.shelf.b2 - 1.19839281085285) < tolerance)
        #expect(abs(filter.shelf.a1 - -1.69065929318241) < tolerance)
        #expect(abs(filter.shelf.a2 - 0.73248077421585) < tolerance)
        #expect(abs(filter.highPass.a1 - -1.99004745483398) < tolerance)
        #expect(abs(filter.highPass.a2 - 0.99007225036621) < tolerance)
    }

    @Test func fullScaleSineIsAboutMinusThreeLUFS() {
        let audio = AudioSamples(samples: Signal.sine(peakDecibels: 0, duration: 5), sampleRate: 48_000)
        #expect(abs(LoudnessMeter.integratedLoudness(of: audio) - -3.01) < 0.05)
    }

    /// EBU Tech 3341, case 1: a 1 kHz sine at −23 dBFS reads −23 LUFS in stereo. Measured as one mono
    /// channel it's 3.01 LU lower.
    @Test(arguments: [48_000.0, 44_100.0, 16_000.0])
    func tech3341CaseOneAsMono(sampleRate: Double) {
        let audio = AudioSamples(
            samples: Signal.sine(frequency: 1000, peakDecibels: -23, duration: 20, sampleRate: sampleRate),
            sampleRate: sampleRate
        )
        #expect(abs(LoudnessMeter.integratedLoudness(of: audio) - -26.01) < 0.1)
    }

    @Test func silenceIsGatedOut() {
        let tone = Signal.sine(frequency: 1000, peakDecibels: -23, duration: 20)
        let audio = AudioSamples(samples: Signal.silence(duration: 10) + tone + Signal.silence(duration: 10), sampleRate: 48_000)
        #expect(abs(LoudnessMeter.integratedLoudness(of: audio) - -26.01) < 0.1)
    }

    /// EBU Tech 3341, case 3: −36, −23, −36 dBFS for 10, 60 and 10 seconds reads −23 LUFS in stereo,
    /// because the relative gate drops the quiet parts.
    @Test func relativeGateDropsQuietParts() {
        let samples = Signal.sine(frequency: 1000, peakDecibels: -36, duration: 10)
            + Signal.sine(frequency: 1000, peakDecibels: -23, duration: 60)
            + Signal.sine(frequency: 1000, peakDecibels: -36, duration: 10)
        let audio = AudioSamples(samples: samples, sampleRate: 48_000)
        #expect(abs(LoudnessMeter.integratedLoudness(of: audio) - -26.01) < 0.1)
    }

    @Test func silenceAndTinyClipsHaveNoLoudness() {
        #expect(LoudnessMeter.integratedLoudness(of: AudioSamples(samples: Signal.silence(duration: 2), sampleRate: 48_000)) == -.infinity)
        #expect(LoudnessMeter.integratedLoudness(of: AudioSamples(samples: [0.5, -0.5], sampleRate: 48_000)) == -.infinity)
    }

    @Test func matchingBringsAudioToTheTarget() {
        let audio = AudioSamples(samples: Signal.sine(frequency: 1000, peakDecibels: -30, duration: 5), sampleRate: 48_000)
        let match = LoudnessMatch(audio, targetLoudness: -23)
        #expect(!match.isPeakLimited)
        #expect(abs(LoudnessMeter.integratedLoudness(of: match.audio) - -23) < 0.05)
        #expect(abs(match.gain - (-23 - match.measuredLoudness)) < 1e-9)
    }

    @Test func matchingNeverPushesThePeakOverTheCeiling() {
        let audio = AudioSamples(samples: Signal.sine(frequency: 1000, peakDecibels: -20, duration: 5), sampleRate: 48_000)
        // −20 dBFS peak is about −23 LUFS; reaching −10 LUFS would need the peak at about −7 dBFS, which
        // fits, but reaching −2 LUFS would need it above 0 dBFS.
        let match = LoudnessMatch(audio, targetLoudness: -2, peakCeiling: -1)
        #expect(match.isPeakLimited)
        #expect(abs(20 * log10(Double(match.audio.peak)) - -1) < 0.01)
    }

    @Test func matchingSilenceLeavesItAlone() {
        let audio = AudioSamples(samples: Signal.silence(duration: 1), sampleRate: 48_000)
        let match = LoudnessMatch(audio, targetLoudness: -23)
        #expect(match.gain == 0)
        #expect(match.audio == audio)
    }
}

@Suite struct CommonLoudnessTests {
    @Test func everyVersionReachesTheCommonLevelUnlimited() {
        // A quiet sine, and a louder one with a sharp peak that limits how far it can be raised.
        let quiet = AudioSamples(samples: Signal.sine(frequency: 1000, peakDecibels: -30, duration: 5), sampleRate: 48_000)
        var spiky = AudioSamples(samples: Signal.sine(frequency: 1000, peakDecibels: -24, duration: 5), sampleRate: 48_000)
        spiky.samples[1_000] = 0.9
        let level = CommonLoudness.level(for: [quiet, spiky], target: -10)
        #expect(level < -10)
        for version in [quiet, spiky] {
            let match = LoudnessMatch(version, targetLoudness: level)
            #expect(!match.isPeakLimited)
            #expect(abs(LoudnessMeter.integratedLoudness(of: match.audio) - level) < 0.05)
        }
    }

    @Test func theTargetIsKeptWhenEveryVersionFitsUnderIt() {
        let quiet = AudioSamples(samples: Signal.sine(frequency: 1000, peakDecibels: -30, duration: 5), sampleRate: 48_000)
        #expect(CommonLoudness.level(for: [quiet], target: -23) == -23)
    }

    @Test func silentVersionsAreIgnored() {
        let silent = AudioSamples(samples: Signal.silence(duration: 2), sampleRate: 48_000)
        #expect(CommonLoudness.level(for: [silent], target: -23) == -23)
    }
}

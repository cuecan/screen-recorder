import Foundation
import ProjectKit

/// The Voice stage: a high-pass, EQ, a compressor and a de-esser, in that order, after Cleanup
/// (docs/design.md, "Audio and transcripts").
///
/// It's plain DSP in Swift rather than Apple's audio units in `AVAudioEngine`, as docs/design.md first
/// planned, for two reasons. Apple's dynamics processor has no ratio parameter, only threshold and head
/// room, so it can't move its ratio toward 1:1 as decision 34 asks. And none of Apple's units is a
/// de-esser. Writing all four stages here also means each one is tested on known signals.
public enum VoiceProcessor {
    /// What a run produced: the audio, and how hard the compressor and de-esser worked.
    public struct Result: Sendable {
        public var audio: AudioSamples
        public var compression: GainReduction?
        public var deEssing: GainReduction?
    }

    /// Which parts of a preset to run, so each can be heard on its own.
    public enum Stages: String, Sendable, Codable, CaseIterable {
        /// The high-pass, EQ, compressor and de-esser.
        case all
        /// The high-pass and EQ only: the preset's tone.
        case eq
        /// The compressor and de-esser only: the preset's dynamics.
        case dynamics
    }

    /// Runs a preset at an amount from 0 to 100 percent. At 0% the audio comes back unchanged.
    public static func process(_ audio: AudioSamples, preset: VoicePreset, amount: Double) -> AudioSamples {
        run(audio, preset: preset, amount: amount).audio
    }

    /// Runs a preset at an amount, and reports how many dB the compressor and de-esser turned the voice down.
    public static func run(_ audio: AudioSamples, preset: VoicePreset, amount: Double, stages: Stages = .all) -> Result {
        guard amount > 0 else { return Result(audio: audio) }
        let scaled = preset.scaled(to: amount)
        let rate = audio.sampleRate
        var samples = audio.samples

        if stages != .dynamics {
            if let highPass = scaled.highPass {
                samples = Biquad.highPass(frequency: highPass, sampleRate: rate).apply(samples)
            }
            for band in scaled.eq {
                samples = Biquad.peaking(frequency: band.frequency, gain: band.gain, q: band.q, sampleRate: rate).apply(samples)
            }
        }

        var result = Result(audio: audio)
        guard stages != .eq else {
            result.audio = AudioSamples(samples: samples, sampleRate: rate)
            return result
        }
        // Each threshold comes from the speech as it reaches that stage.
        if let threshold = SpeechPeaks.threshold(samples, sampleRate: rate, percentile: scaled.compression.thresholdPercentile) {
            let output = compressor(for: scaled.compression, threshold: threshold).process(samples, sampleRate: rate)
            samples = output.samples
            result.compression = GainReduction(output.reduction)
        }
        if let deEsser = scaled.deEsser, let bandHighPass = deEsser.bandHighPass {
            let band = Biquad.highPass(frequency: bandHighPass, sampleRate: rate).applyZeroPhase(samples)
            if let threshold = SpeechPeaks.threshold(band, sampleRate: rate, percentile: deEsser.thresholdPercentile) {
                let output = compressor(for: deEsser, threshold: threshold).process(samples, sampleRate: rate)
                samples = output.samples
                result.deEssing = GainReduction(output.reduction)
            }
        }
        result.audio = AudioSamples(samples: samples, sampleRate: rate)
        return result
    }

    static func compressor(for compression: VoicePreset.Compression, threshold: Double) -> Compressor {
        Compressor(
            threshold: threshold,
            ratio: compression.ratio,
            attack: compression.attack,
            release: compression.release,
            makeUpGain: compression.makeUpGain,
            maximumReduction: compression.maximumReduction,
            bandHighPass: compression.bandHighPass,
            lookahead: compression.lookahead
        )
    }
}

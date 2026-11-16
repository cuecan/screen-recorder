import Foundation

/// The Loudness stage: the final mix brought to the export loudness with gain, its true peaks held under
/// the ceiling by ``TruePeakLimiter`` (docs/decisions.md, 35).
///
/// Limiting lowers the loudness a little, so the loudness is measured again after limiting and the gain
/// corrected, until it lands within 0.1 LU of the target.
public enum LoudnessStage {
    public struct Output: Sendable {
        public var audio: AudioSamples
        /// The loudness before, in LUFS.
        public var inputLoudness: Double
        /// The gain applied before the limiter, in dB.
        public var gain: Double
        /// The most the limiter turned down at any moment, in dB.
        public var limiterReduction: Double
        /// The loudness after, in LUFS.
        public var loudness: Double
        /// The true peak after, in dBTP.
        public var truePeak: Double
    }

    public static func process(_ audio: AudioSamples, target: Double = -14, ceiling: Double = -1) -> Output {
        process(audio, target: target, ceiling: ceiling, checkpoint: {})
    }

    /// `checkpoint` lets an export stop between bounded runs of samples, including while mastering.
    public static func process(_ audio: AudioSamples, target: Double = -14, ceiling: Double = -1,
                               checkpoint: () throws -> Void) rethrows -> Output {
        try checkpoint()
        let measured = try LoudnessMeter.integratedLoudness(of: audio, checkpoint: checkpoint)
        guard measured.isFinite else {
            let limited = try TruePeakLimiter(ceiling: ceiling).process(audio, checkpoint: checkpoint)
            return Output(audio: limited.audio, inputLoudness: measured, gain: 0, limiterReduction: limited.maximumReduction, loudness: measured, truePeak: limited.truePeak)
        }
        let limiter = TruePeakLimiter(ceiling: ceiling)
        var gain = target - measured
        var limited = try limiter.process(audio.applyingGain(decibels: gain, checkpoint: checkpoint), checkpoint: checkpoint)
        var loudness = try LoudnessMeter.integratedLoudness(of: limited.audio, checkpoint: checkpoint)
        // Under heavy limiting, each extra dB of gain adds less than 1 dB of loudness, so after the first
        // correction each step uses how much loudness the last one actually bought (the secant method).
        var previous: (gain: Double, loudness: Double)?
        for _ in 0..<8 where abs(loudness - target) > 0.1 {
            var step = target - loudness
            if let previous, abs(loudness - previous.loudness) > 0.01 {
                let slope = (loudness - previous.loudness) / (gain - previous.gain)
                step /= min(1, max(0.1, slope))
            }
            previous = (gain, loudness)
            gain += step
            limited = try limiter.process(audio.applyingGain(decibels: gain, checkpoint: checkpoint), checkpoint: checkpoint)
            loudness = try LoudnessMeter.integratedLoudness(of: limited.audio, checkpoint: checkpoint)
        }
        return Output(
            audio: limited.audio,
            inputLoudness: measured,
            gain: gain,
            limiterReduction: limited.maximumReduction,
            loudness: loudness,
            truePeak: limited.truePeak
        )
    }
}

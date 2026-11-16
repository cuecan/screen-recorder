import Foundation

/// A copy of some audio brought to a target loudness with plain gain, for listening side by side.
///
/// Judging cleanup by ear only works at equal loudness, because the louder of two versions tends to
/// sound better. No limiter or compressor is used: if the gain would push the true peak above
/// `peakCeiling` (dBTP), the gain is lowered to fit, and ``isPeakLimited`` says the copy came out quieter
/// than the target. To compare several versions at one level, pick the level with ``CommonLoudness``.
public struct LoudnessMatch: Sendable {
    public var audio: AudioSamples
    /// The loudness before the gain, in LUFS.
    public var measuredLoudness: Double
    /// The gain applied, in dB.
    public var gain: Double
    /// Whether the gain was lowered to keep the peak under the ceiling.
    public var isPeakLimited: Bool

    public init(_ source: AudioSamples, targetLoudness: Double, peakCeiling: Double = -1) {
        let measured = LoudnessMeter.integratedLoudness(of: source)
        var gain = LoudnessMeter.gain(toReach: targetLoudness, from: measured)
        let peak = TruePeakMeter.truePeak(of: source)
        var limited = false
        if peak.isFinite {
            let peakAfterGain = peak + gain
            if peakAfterGain > peakCeiling {
                gain -= peakAfterGain - peakCeiling
                limited = true
            }
        }
        self.audio = source.applyingGain(decibels: gain)
        self.measuredLoudness = measured
        self.gain = gain
        self.isPeakLimited = limited
    }
}

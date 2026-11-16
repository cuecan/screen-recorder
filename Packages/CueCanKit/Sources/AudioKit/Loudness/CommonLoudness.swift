import Foundation

/// The loudness every one of several versions can be brought to with plain gain, without any of them
/// reaching a true-peak ceiling (dBTP).
///
/// Comparing versions by ear only works when they're equally loud. Matching each to a fixed target and
/// lowering the ones that would clip leaves them at different levels, so this finds one level that all of
/// them reach: the target, or lower if any version's peak won't allow it.
public enum CommonLoudness {
    /// - Returns: The level in LUFS, at most `target`. Versions that are silent are ignored.
    public static func level(for versions: [AudioSamples], target: Double, peakCeiling: Double = -1) -> Double {
        var level = target
        for version in versions {
            let loudness = LoudnessMeter.integratedLoudness(of: version)
            let peak = TruePeakMeter.truePeak(of: version)
            guard loudness.isFinite, peak.isFinite else { continue }
            // Gain moves loudness and peak together, so the peak reaches the ceiling at this loudness.
            level = min(level, loudness + (peakCeiling - peak))
        }
        return level
    }
}

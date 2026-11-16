import Foundation

/// The audio lane's readable peak scale. Apply the clip's gain before compressing the display range,
/// so quiet peaks can grow into view, and Off remains silent at every input level.
public enum WaveformScale {
    public static let floorDecibels = -50.0

    /// A fraction of the waveform band's height, from a measured linear peak and clip gain in dB.
    public static func height(peak: Double, gain: Double) -> Double {
        guard peak.isFinite, peak > 0, SoundLevel.clamped(gain) > SoundLevel.range.lowerBound else { return 0 }
        let decibels = 20 * log10(peak) + SoundLevel.clamped(gain)
        return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }
}

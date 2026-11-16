import Foundation

/// The mic's level over one short window, about 20 ms: what one bar of the widget's waveform shows.
public struct LevelSample: Sendable, Equatable {
    /// The highest sample's size, 0 to 1 (full scale).
    public var peak: Float
    /// The window's root-mean-square level, 0 to 1.
    public var rms: Float

    public init(peak: Float, rms: Float) {
        self.peak = peak
        self.rms = rms
    }

    public static let silence = LevelSample(peak: 0, rms: 0)

    /// The peak in dBFS, down to −120 for silence.
    public var peakDecibels: Float { Self.decibels(peak) }
    public var rmsDecibels: Float { Self.decibels(rms) }

    static func decibels(_ value: Float) -> Float {
        value > 0 ? max(-120, 20 * log10(value)) : -120
    }
}

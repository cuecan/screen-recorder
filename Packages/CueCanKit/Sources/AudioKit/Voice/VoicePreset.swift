import Foundation
import ProjectKit

/// The settings behind a Voice preset: a high-pass, EQ bands, a compressor and an optional de-esser
/// (docs/decisions.md, 33 and 34).
///
/// The values sit in the ranges published guides give for spoken voice:
/// - **Compressor:** ratio 3:1 to 5:1 (4:1 the usual start), attack 1 to 5 ms, release 100 to 200 ms.
/// - **High-pass:** around 80 Hz for spoken word.
/// - **EQ:** warmth at about 150 to 300 Hz (lifted 1 to 3 dB), boxiness at about 300 to 500 Hz, nasal honk
///   at about 800 Hz to 1.5 kHz (cut 1 to 2 dB).
///
/// The exact frequencies and amounts within those ranges, the thresholds, the look-ahead and the de-esser
/// are starting points to tune by ear in the bake-off (TEST NEEDED).
///
/// A threshold is set by how much of the speech it touches, not as a level: it's the peak level that a
/// percentage of the voice's 50 ms stretches stay under (``SpeechPeaks``). So a preset compresses a quiet
/// laptop mic and a hot studio mic the same way.
public struct VoicePreset: Equatable, Sendable {
    /// A peaking EQ band.
    public struct Band: Equatable, Sendable {
        public var frequency: Double
        public var gain: Double
        public var q: Double
    }

    /// A compressor.
    public struct Compression: Equatable, Sendable {
        /// The threshold, as the percentage of speech stretches whose peaks stay under it. 50 compresses the
        /// louder half of the speech; 30 compresses the loudest 70 percent.
        public var thresholdPercentile: Double
        public var ratio: Double
        public var attack: TimeInterval
        public var release: TimeInterval
        /// How far ahead the gain looks, so it's already coming down when a peak arrives.
        public var lookahead: TimeInterval
        public var makeUpGain: Double
        /// For the de-esser: where its band starts, and the most it turns that band down.
        public var bandHighPass: Double?
        public var maximumReduction: Double?
    }

    public var highPass: Double?
    /// Peaking EQ bands, applied in order after the high-pass.
    public var eq: [Band]
    public var compression: Compression
    public var deEsser: Compression?

    /// Gentle: for a decent mic in a decent room. A light boxiness cut and a little presence, and the low end
    /// of the usual ratio range on the louder half of the speech.
    public static let clear = VoicePreset(
        highPass: 80,
        eq: [
            Band(frequency: 400, gain: -1.5, q: 1.0),
            Band(frequency: 4_000, gain: 2, q: 0.8),
        ],
        compression: Compression(
            thresholdPercentile: 50, ratio: 3, attack: 0.005, release: 0.15, lookahead: 0.005, makeUpGain: 1
        ),
        deEsser: nil
    )

    /// Stronger and warmer: the close, full sound of a voiceover. A warmth lift where a close mic's body is,
    /// a small cut where a voice turns nasal, a little presence, and the usual 4:1 on the loudest 70 percent
    /// of the speech, with a de-esser on the loudest sibilance.
    ///
    /// The first version cut 3 dB around 300 Hz and lifted 4 dB around 4.5 kHz, which took out the body and
    /// left the voice nasal on an SM7B.
    public static let broadcast = VoicePreset(
        highPass: 80,
        eq: [
            Band(frequency: 200, gain: 2, q: 0.8),
            Band(frequency: 1_000, gain: -1.5, q: 1.0),
            Band(frequency: 4_500, gain: 2, q: 0.8),
        ],
        compression: Compression(
            thresholdPercentile: 30, ratio: 4, attack: 0.003, release: 0.1, lookahead: 0.003, makeUpGain: 3
        ),
        deEsser: Compression(
            thresholdPercentile: 80, ratio: 4, attack: 0.001, release: 0.05, lookahead: 0.001, makeUpGain: 0,
            bandHighPass: 6_000, maximumReduction: 8
        )
    )

    public static func preset(_ preset: VoiceSettings.Preset) -> VoicePreset? {
        switch preset {
        case .off: nil
        case .clear: .clear
        case .broadcast: .broadcast
        }
    }

    /// The preset at an amount from 0 to 100 percent, as decision 34 describes:
    /// - EQ moves scale with the amount: at 50% they're half as big.
    /// - Compression ratios move toward 1:1, and make-up gain follows the compression. Thresholds stay.
    /// - The de-esser's largest reduction scales too.
    /// - The high-pass is on at any amount above 0, since it only removes rumble below the voice.
    ///
    /// At 0% the result changes nothing.
    public func scaled(to amount: Double) -> VoicePreset {
        let fraction = min(100, max(0, amount)) / 100
        var preset = self
        preset.highPass = fraction > 0 ? highPass : nil
        preset.eq = eq.map { band in
            var scaled = band
            scaled.gain = band.gain * fraction
            return scaled
        }
        preset.compression = Self.scale(compression, by: fraction)
        preset.deEsser = deEsser.map { Self.scale($0, by: fraction) }
        return preset
    }

    private static func scale(_ compression: Compression, by fraction: Double) -> Compression {
        var scaled = compression
        scaled.ratio = 1 + (compression.ratio - 1) * fraction
        // Make-up gain follows how hard it compresses, which is (1 − 1/ratio).
        let fullDepth = 1 - 1 / compression.ratio
        let depth = 1 - 1 / scaled.ratio
        scaled.makeUpGain = fullDepth > 0 ? compression.makeUpGain * depth / fullDepth : 0
        scaled.maximumReduction = compression.maximumReduction.map { $0 * fraction }
        return scaled
    }
}

import Foundation

/// A level of sound in decibels of gain: a clip's voice or system audio, or an overlay's own sound
/// (docs/decisions.md, 71). 0 dB plays it as recorded. Exports are levelled to −14 LUFS afterwards, so
/// levels only set the balance.
public enum SoundLevel {
    /// The quietest and loudest a level can be set. At the bottom it's silent.
    public static let range: ClosedRange<Double> = -60...12

    /// A gain in decibels as a volume to multiply by; silent at the bottom of the range.
    public static func volume(forGain gain: Double) -> Double {
        gain <= range.lowerBound ? 0 : pow(10, gain / 20)
    }

    /// A level brought into ``range``; anything not finite is 0 dB.
    public static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 0
    }

    /// How a level reads to a creator: "Off" at the bottom, then "−6 dB", "0 dB" or "+3 dB", to the
    /// nearest decibel.
    public static func label(_ gain: Double) -> String {
        guard gain > range.lowerBound else { return "Off" }
        let rounded = Int(gain.rounded())
        return rounded > 0 ? "+\(rounded) dB" : rounded < 0 ? "−\(-rounded) dB" : "0 dB"
    }
}

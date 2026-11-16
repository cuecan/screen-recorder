import Foundation

/// The timeline's audio lane, in the lane's own points (docs/decisions.md, 71 and 74): the voice's waveform
/// with each clip's level line across it, the words under it once zoomed in, and system audio's thinner
/// waveform at the bottom. Drawing and hit testing share these numbers.
public enum AudioLane {
    /// How close to a level line, in points, a press picks it up.
    public static let grab = 4.0

    /// Where the voice's waveform and level lines are drawn.
    public static var voice: ClosedRange<Double> {
        let top = TimelineLane.audio.top + 4
        return top...(top + 34)
    }

    /// Where the words are written once zoomed in, just under the voice's waveform (docs/decisions.md, 74).
    /// Nothing here is clicked: the transcript is where words are picked and fixed.
    public static var words: ClosedRange<Double> {
        (voice.upperBound + 1)...(voice.upperBound + 15)
    }

    /// Where system audio's waveform is drawn, under the words.
    public static var system: ClosedRange<Double> {
        (words.upperBound + 2)...(TimelineLane.audio.top + TimelineLane.audio.height - 4)
    }

    /// Where 0 dB sits, as a fraction of the way up the voice's band: three-quarters, with +12 dB at the top.
    static let unity = 0.75

    /// How far up the voice's band a level's line sits, from 0 at the bottom (off) to 1 at the top (+12 dB).
    /// Above 0 dB it's even; below, the scale opens out near 0 dB, where most changes are, most of a point a
    /// decibel there.
    public static func fraction(of level: Double) -> Double {
        let level = SoundLevel.clamped(level)
        let range = SoundLevel.range
        if level >= 0 { return unity + (1 - unity) * level / range.upperBound }
        let down = 1 - level / range.lowerBound
        return unity * down * down
    }

    /// The level whose line sits at a fraction of the way up the voice's band, to the nearest decibel.
    public static func level(atFraction fraction: Double) -> Double {
        let fraction = min(max(fraction, 0), 1)
        let range = SoundLevel.range
        let level = fraction >= unity
            ? (fraction - unity) / (1 - unity) * range.upperBound
            : range.lowerBound * (1 - (fraction / unity).squareRoot())
        return SoundLevel.clamped(level.rounded())
    }

    /// The level line's height in the timeline, in points from its top.
    public static func lineY(for level: Double) -> Double {
        let band = voice
        let span = band.upperBound - band.lowerBound - 4
        return band.upperBound - 2 - fraction(of: level) * span
    }

    /// The level a line at this height in the timeline sets.
    public static func level(atY y: Double) -> Double {
        let band = voice
        let span = band.upperBound - band.lowerBound - 4
        return level(atFraction: (band.upperBound - 2 - y) / span)
    }
}

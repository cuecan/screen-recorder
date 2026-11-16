import Accelerate
import Foundation

/// Finds when each of the sync page's beeps reached the mic (docs/decisions.md, 83).
///
/// The beep is one steady pitch that starts at full strength. The sound is measured in short windows for
/// how much of that pitch it holds, and how much of the window's sound is that pitch at all, so speech and
/// knocks aren't taken for beeps. A beep starts where the pitch reaches half its strength: a window is
/// half full of the tone when the tone began at its middle.
public enum BeepDetector {
    /// The window the pitch is measured over, and how far it moves each time, in seconds.
    static let window = 0.004
    static let hop = 0.001
    /// The quietest a beep can be, as the tone's amplitude of full scale (about −54 dBFS). A starting value.
    public static let minimumLevel: Float = 0.002
    /// How much of a window's sound has to be the tone, from 0 to 1. A starting value.
    static let minimumPurity: Float = 0.5
    /// How long the tone has to last to be a beep, and how near two beeps can be, in seconds.
    static let minimumLength = 0.05
    static let refractory = 0.8

    /// When each beep began, in the clock `startTime` is on.
    public static func onsets(in samples: [Float], sampleRate: Double, startTime: TimeInterval,
                              frequency: Double = SyncSignal.beepFrequency) -> [TimeInterval] {
        let size = Int((window * sampleRate).rounded())
        let step = Int((hop * sampleRate).rounded())
        guard size > 0, step > 0, samples.count >= size else { return [] }
        let turn = 2 * Double.pi * frequency / sampleRate
        let cosines = (0..<size).map { Float(cos(turn * Double($0))) }
        let sines = (0..<size).map { Float(sin(turn * Double($0))) }

        // Each window's tone, as an amplitude, and the same kept only where the window is mostly tone.
        let count = (samples.count - size) / step + 1
        var strength = [Float](repeating: 0, count: count)
        var tonal = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { sound in
            guard let first = sound.baseAddress else { return }
            for index in 0..<count {
                let start = first + index * step
                var real: Float = 0, imaginary: Float = 0, energy: Float = 0
                vDSP_dotpr(start, 1, cosines, 1, &real, vDSP_Length(size))
                vDSP_dotpr(start, 1, sines, 1, &imaginary, vDSP_Length(size))
                vDSP_svesq(start, 1, &energy, vDSP_Length(size))
                let power = real * real + imaginary * imaginary
                strength[index] = 2 * power.squareRoot() / Float(size)
                if energy > 0, 2 * power / Float(size) / energy >= minimumPurity { tonal[index] = strength[index] }
            }
        }
        guard let loudest = tonal.max(), loudest >= minimumLevel else { return [] }

        let reach = Int(0.06 / hop)
        let length = Int(minimumLength / hop)
        var onsets: [TimeInterval] = []
        var index = 0
        while index < count {
            defer { index += 1 }
            guard tonal[index] >= loudest / 4 else { continue }
            let peak = tonal[index..<min(count, index + reach)].max() ?? tonal[index]
            // A beep goes on; a knock that happens to hold the pitch doesn't.
            let lasting = tonal[index..<min(count, index + 3 * length)].count { $0 >= peak / 4 }
            guard lasting >= length else { continue }
            let half = peak / 2
            let start = max(1, index - 2 * size / step)
            guard let crossing = (start..<min(count, index + reach)).first(where: { strength[$0] >= half && strength[$0 - 1] < half })
            else { continue }
            let fraction = Double((half - strength[crossing - 1]) / (strength[crossing] - strength[crossing - 1]))
            let time = startTime + (Double(crossing - 1) + fraction) * hop + window / 2
            if let last = onsets.last, time - last < refractory { continue }
            onsets.append(time)
            index += Int(refractory / hop) / 2
        }
        return onsets
    }
}

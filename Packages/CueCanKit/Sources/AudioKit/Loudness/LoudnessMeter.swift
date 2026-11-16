import Foundation

/// Integrated loudness in LUFS, measured as ITU-R BS.1770-4 and EBU R 128 define it.
///
/// K-weighted mean square over 400 ms blocks overlapping by 75%. Blocks below −70 LUFS are gated out,
/// then blocks more than 10 LU below the loudness of what's left. Mono is measured as a single channel
/// with weight 1, as libebur128 does by default, so a full-scale 1 kHz sine reads about −3 LUFS.
///
/// This is a pure-Swift stand-in for libebur128 (docs/decisions.md, 22), tested against the reference
/// signals in EBU Tech 3341. It measures; it doesn't change the audio.
public enum LoudnessMeter {
    /// The loudness of silence or of audio too short to hold one 400 ms block.
    public static let silence = -Double.infinity

    public static func integratedLoudness(of audio: AudioSamples) -> Double { integratedLoudness(of: audio, checkpoint: {}) }

    /// Checks for cancellation during measurement without changing the calculated loudness.
    public static func integratedLoudness(of audio: AudioSamples, checkpoint: () throws -> Void) rethrows -> Double {
        try checkpoint()
        let blockLength = Int((0.4 * audio.sampleRate).rounded())
        let step = Int((0.1 * audio.sampleRate).rounded())
        guard blockLength > 0, step > 0, audio.samples.count >= blockLength else { return silence }

        var filter = KWeightingFilter.Processor(filter: KWeightingFilter(sampleRate: audio.sampleRate))
        // Keep just one block of cumulative sums. Addition and subtraction have the same order as the
        // full-recording arrays, so the measurement stays identical without two large Double buffers.
        var cumulative = [Double](repeating: 0, count: blockLength + 1)
        var sum = 0.0
        var blockPowers: [Double] = []
        for index in audio.samples.indices {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            let weighted = filter.process(audio.samples[index])
            sum += weighted * weighted
            let end = index + 1
            cumulative[end % cumulative.count] = sum
            let start = end - blockLength
            if start >= 0, start.isMultiple(of: step) {
                blockPowers.append((sum - cumulative[start % cumulative.count]) / Double(blockLength))
            }
        }

        let absoluteGate = power(forLoudness: -70)
        let aboveAbsolute = blockPowers.filter { $0 > absoluteGate }
        guard !aboveAbsolute.isEmpty else { return silence }
        let relativeGate = mean(aboveAbsolute) * pow(10, -10.0 / 10)
        let gated = aboveAbsolute.filter { $0 > relativeGate }
        guard !gated.isEmpty else { return silence }
        return loudness(forPower: mean(gated))
    }

    /// The gain in decibels that brings audio to a target loudness.
    public static func gain(toReach target: Double, from measured: Double) -> Double {
        measured.isFinite ? target - measured : 0
    }

    static func loudness(forPower power: Double) -> Double {
        -0.691 + 10 * log10(power)
    }

    static func power(forLoudness loudness: Double) -> Double {
        pow(10, (loudness + 0.691) / 10)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}

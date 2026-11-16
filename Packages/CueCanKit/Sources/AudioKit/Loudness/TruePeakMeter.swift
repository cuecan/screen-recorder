import Accelerate
import Foundation

/// The true peak of audio in dBTP, as ITU-R BS.1770-4 Annex 2 describes: the signal is oversampled (4× below
/// 96 kHz, 2× below 192 kHz) and the largest absolute value is taken, so peaks between samples count.
///
/// The interpolator is a windowed-sinc polyphase filter with 24 taps per phase, rather than the example
/// filter printed in the standard. It's tested against signals whose true peak is known.
public enum TruePeakMeter {
    static let tapsPerPhase = 24

    /// The true peak in dBTP, or −∞ for silence.
    public static func truePeak(of audio: AudioSamples) -> Double { truePeak(of: audio, checkpoint: {}) }

    /// The same measurement with cancellation checkpoints.
    public static func truePeak(of audio: AudioSamples, checkpoint: () throws -> Void) rethrows -> Double {
        let linear = try linearTruePeak(of: audio, checkpoint: checkpoint)
        return linear > 0 ? 20 * log10(Double(linear)) : -.infinity
    }

    /// The true peak as a linear amplitude, where 1 is full scale.
    public static func linearTruePeak(of audio: AudioSamples) -> Float { linearTruePeak(of: audio, checkpoint: {}) }

    /// The same measurement with cancellation checkpoints.
    public static func linearTruePeak(of audio: AudioSamples, checkpoint: () throws -> Void) rethrows -> Float {
        try checkpoint()
        let factor = oversampling(for: audio.sampleRate)
        let samples = audio.samples
        guard !samples.isEmpty else { return 0 }
        var peak: Float = 0
        for index in samples.indices {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            peak = max(peak, abs(samples[index]))
        }
        guard factor > 1 else { return peak }

        let taps = tapsPerPhase
        // Pad so every output sample sees a full window; vDSP_conv correlates, so phases are stored reversed.
        let half = taps / 2
        let padded = [Float](repeating: 0, count: half) + samples + [Float](repeating: 0, count: taps)
        var output = [Float](repeating: 0, count: samples.count + half)
        for phase in phaseFilters(factor: factor) {
            try checkpoint()
            vDSP_conv(padded, 1, phase, 1, &output, 1, vDSP_Length(output.count), vDSP_Length(taps))
            var phasePeak: Float = 0
            vDSP_maxmgv(output, 1, &phasePeak, vDSP_Length(output.count))
            peak = max(peak, phasePeak)
        }
        return peak
    }

    /// For each sample, the highest absolute value the oversampled signal reaches from that sample up to
    /// the next: what a true-peak limiter has to keep under its ceiling.
    public static func peakEnvelope(of audio: AudioSamples) -> [Float] { peakEnvelope(of: audio, checkpoint: {}) }

    /// The same measurement with cancellation checkpoints.
    public static func peakEnvelope(of audio: AudioSamples, checkpoint: () throws -> Void) rethrows -> [Float] {
        try checkpoint()
        let samples = audio.samples
        var envelope = [Float](repeating: 0, count: samples.count)
        for index in samples.indices {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            envelope[index] = abs(samples[index])
        }
        let factor = oversampling(for: audio.sampleRate)
        guard factor > 1, !samples.isEmpty else { return envelope }

        let taps = tapsPerPhase
        let half = taps / 2
        let padded = [Float](repeating: 0, count: half) + samples + [Float](repeating: 0, count: taps)
        var output = [Float](repeating: 0, count: samples.count + half)
        for phase in phaseFilters(factor: factor) {
            try checkpoint()
            vDSP_conv(padded, 1, phase, 1, &output, 1, vDSP_Length(output.count), vDSP_Length(taps))
            // Phase p's output at n + 1 is the signal at n + p/factor (see phaseFilters' centring).
            for index in samples.indices {
                if index.isMultiple(of: 16_384) { try checkpoint() }
                envelope[index] = max(envelope[index], abs(output[index + 1]))
            }
        }
        return envelope
    }

    static func oversampling(for sampleRate: Double) -> Int {
        if sampleRate < 96_000 { return 4 }
        if sampleRate < 192_000 { return 2 }
        return 1
    }

    /// One filter per output phase, each normalized to unity gain at DC and stored reversed for `vDSP_conv`.
    static func phaseFilters(factor: Int) -> [[Float]] {
        let length = factor * tapsPerPhase
        // Centred on a tap, so phase 0 passes the samples through and the others fall at exact fractions
        // of a sample (¼, ½ and ¾ at 4×), including halfway, where a peak between two samples sits.
        let center = Double(length) / 2
        let prototype = (0..<length).map { index -> Double in
            let x = (Double(index) - center) / Double(factor)
            let sinc = x == 0 ? 1 : sin(Double.pi * x) / (Double.pi * x)
            // Blackman window, symmetric about the centre tap.
            let position = Double(index) / Double(length)
            let window = 0.42 - 0.5 * cos(2 * .pi * position) + 0.08 * cos(4 * .pi * position)
            return sinc * window
        }
        return (0..<factor).map { phase in
            let taps = stride(from: phase, to: length, by: factor).map { prototype[$0] }
            let sum = taps.reduce(0, +)
            return taps.reversed().map { Float($0 / sum) }
        }
    }
}

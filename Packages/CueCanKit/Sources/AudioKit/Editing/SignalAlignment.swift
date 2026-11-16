import Accelerate
import Foundation

/// How a processed version of a recording lines up with the original: its offset in samples and its
/// gain. A blend of the two only sounds clean when both are corrected to the sample, or it combs and
/// sounds phasey (docs/decisions.md, 34).
public struct SignalAlignment: Sendable, Equatable, Codable {
    /// How many samples later the processed version is: `processed[i + lag]` lines up with `original[i]`.
    /// Negative when the processed version is early.
    public var lag: Int
    /// The normalized correlation at that lag, from −1 to 1. Near 1 means the processed version still
    /// follows the original's waveform; low means it doesn't, as when a model rebuilds the voice, and a
    /// blend will sound doubled whatever the offset.
    public var correlation: Double
    /// The gain that brings the processed version to the original's level, so a blend doesn't change level
    /// as the dial moves. See ``method`` for how it was found.
    public var gain: Double
    /// How the lag and gain were found.
    public var method: Method

    /// How an alignment was measured.
    public enum Method: String, Sendable, Codable {
        /// From the waveforms: the lag to the sample, and the least-squares gain. Noise that a model
        /// removed doesn't correlate, so it doesn't sway the gain.
        case waveform
        /// From the loudness envelopes, to the millisecond, with the gain matching integrated loudness.
        /// Used when the waveform doesn't follow the original (``correlation`` below
        /// ``SignalAlignment/waveformThreshold``), as when a model rebuilds the voice. A waveform lag and
        /// least-squares gain are meaningless then.
        case envelope
    }

    /// Below this waveform correlation, the envelope method is used. A judgment call, not a measured
    /// value (TEST NEEDED): denoisers on real recordings land well above it, and a rebuilt voice well below.
    public static let waveformThreshold = 0.5

    public init(lag: Int, correlation: Double, gain: Double, method: Method = .waveform) {
        self.lag = lag
        self.correlation = correlation
        self.gain = gain
        self.method = method
    }

    /// Measures the alignment over a stretch from the middle of the recording.
    ///
    /// The search is coarse first, on both signals averaged down by 8, then sample by sample around the
    /// best coarse lag.
    ///
    /// - Parameters:
    ///   - maximumLag: The largest offset to look for, either way, in seconds.
    ///   - window: How much of the recording to compare, in seconds.
    public static func measure(
        original: AudioSamples,
        processed: AudioSamples,
        maximumLag: TimeInterval = 0.5,
        window: TimeInterval = 20
    ) -> SignalAlignment {
        let reference = original.samples
        let signal = processed.samples
        let decimation = 8
        let maxLag = Int(maximumLag * original.sampleRate) / decimation * decimation
        let available = min(reference.count, signal.count) - 2 * maxLag
        let length = min(Int(window * original.sampleRate), available) / decimation * decimation
        guard length > 64 else { return SignalAlignment(lag: 0, correlation: 0, gain: 1) }
        let start = maxLag + (available - length) / 2

        // Coarse: both signals summed in blocks of 8, then the processed one slid a block at a time.
        let coarseReference = decimate(reference, from: start, count: length, by: decimation)
        let coarseSignal = decimate(signal, from: start - maxLag, count: length + 2 * maxLag, by: decimation)
        let blocks = coarseReference.count
        var bestCoarse = 0
        var bestScore = -Double.infinity
        coarseSignal.withUnsafeBufferPointer { buffer in
            for step in 0...(2 * maxLag / decimation) {
                let slice = UnsafeBufferPointer(rebasing: buffer[step..<(step + blocks)])
                let score = Double(vDSP.dot(coarseReference, slice))
                if score > bestScore {
                    bestScore = score
                    bestCoarse = step * decimation - maxLag
                }
            }
        }

        // Fine: every sample around the coarse best.
        let referenceWindow = Array(reference[start..<(start + length)])
        let referenceEnergy = Double(vDSP.sumOfSquares(referenceWindow))
        var best = SignalAlignment(lag: 0, correlation: -.infinity, gain: 1)
        let fineLags = max(-maxLag, bestCoarse - 2 * decimation)...min(maxLag, bestCoarse + 2 * decimation)
        for lag in fineLags {
            let signalWindow = Array(signal[(start + lag)..<(start + lag + length)])
            let product = Double(vDSP.dot(referenceWindow, signalWindow))
            let signalEnergy = Double(vDSP.sumOfSquares(signalWindow))
            guard referenceEnergy > 0, signalEnergy > 0 else { continue }
            let correlation = product / (referenceEnergy * signalEnergy).squareRoot()
            if correlation > best.correlation {
                best = SignalAlignment(lag: lag, correlation: correlation, gain: product / signalEnergy)
            }
        }
        guard best.correlation.isFinite else { return SignalAlignment(lag: 0, correlation: 0, gain: 1) }
        guard best.correlation < waveformThreshold else { return best }
        return envelopeAlignment(original: original, processed: processed, correlation: best.correlation, maxLag: maxLag, start: start, length: length)
    }

    /// Lines up two versions by their loudness envelopes, which still match when the waveforms don't, and
    /// matches their integrated loudness.
    static func envelopeAlignment(
        original: AudioSamples,
        processed: AudioSamples,
        correlation: Double,
        maxLag: Int,
        start: Int,
        length: Int
    ) -> SignalAlignment {
        let block = max(1, Int(original.sampleRate / 1_000))  // 1 ms
        let reference = envelope(original.samples, from: start, count: length, block: block)
        let signal = envelope(processed.samples, from: start - maxLag, count: length + 2 * maxLag, block: block)
        let blocks = reference.count
        let steps = (2 * maxLag) / block
        var bestStep = maxLag / block
        var bestScore = -Double.infinity
        signal.withUnsafeBufferPointer { buffer in
            for step in 0...steps where step + blocks <= buffer.count {
                let slice = Array(buffer[step..<(step + blocks)])
                let score = Double(vDSP.dot(reference, slice))
                if score > bestScore {
                    bestScore = score
                    bestStep = step
                }
            }
        }
        let lag = bestStep * block - maxLag
        let originalLoudness = LoudnessMeter.integratedLoudness(of: original)
        let processedLoudness = LoudnessMeter.integratedLoudness(of: processed)
        let gain = originalLoudness.isFinite && processedLoudness.isFinite
            ? pow(10, (originalLoudness - processedLoudness) / 20)
            : 1
        return SignalAlignment(lag: lag, correlation: correlation, gain: gain, method: .envelope)
    }

    /// RMS per block, with its mean removed so the correlation follows the shape, not the level.
    private static func envelope(_ samples: [Float], from start: Int, count: Int, block: Int) -> [Float] {
        let blocks = count / block
        var output = [Float](repeating: 0, count: blocks)
        for index in 0..<blocks {
            let base = start + index * block
            var sum: Float = 0
            for offset in 0..<block {
                let value = samples[base + offset]
                sum += value * value
            }
            output[index] = (sum / Float(block)).squareRoot()
        }
        let mean = output.reduce(0, +) / Float(max(1, blocks))
        return output.map { $0 - mean }
    }

    /// The processed version shifted by ``lag`` and scaled by ``gain``, cut or padded to `length` samples,
    /// so it lines up with the original sample for sample.
    public func apply(to processed: AudioSamples, length: Int) -> AudioSamples {
        let factor = Float(gain)
        var output = [Float](repeating: 0, count: length)
        processed.samples.withUnsafeBufferPointer { source in
            for index in 0..<length {
                let from = index + lag
                if from >= 0, from < source.count {
                    output[index] = source[from] * factor
                }
            }
        }
        return AudioSamples(samples: output, sampleRate: processed.sampleRate)
    }

    /// Mixes an aligned processed version with the original: `amount` 100 is all processed, 0 all original.
    public static func blend(original: AudioSamples, aligned: AudioSamples, amount: Double) -> AudioSamples {
        let wet = Float(min(100, max(0, amount)) / 100)
        let count = min(original.samples.count, aligned.samples.count)
        let output = (0..<count).map { wet * aligned.samples[$0] + (1 - wet) * original.samples[$0] }
        return AudioSamples(samples: output, sampleRate: original.sampleRate)
    }

    private static func decimate(_ samples: [Float], from start: Int, count: Int, by factor: Int) -> [Float] {
        let blocks = count / factor
        var output = [Float](repeating: 0, count: blocks)
        for block in 0..<blocks {
            var sum: Float = 0
            let base = start + block * factor
            for offset in 0..<factor { sum += samples[base + offset] }
            output[block] = sum
        }
        return output
    }
}

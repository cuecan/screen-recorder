import Foundation

/// A look-ahead brickwall limiter on true peak: the last stage of the export, so no peak between samples
/// goes over the ceiling after YouTube re-encodes the audio (docs/decisions.md, 35).
///
/// 1. For each sample, the gain that keeps its true peak at the ceiling (``TruePeakMeter/peakEnvelope(of:)``).
/// 2. The lowest of those over the look-ahead window, so the gain is down before a peak arrives.
/// 3. A moving average over the same window, which smooths the gain without ever rising above what step 2
///    allows, so the ceiling holds.
/// 4. A release, so the gain comes back up gradually after a peak.
///
/// A gain that changes from sample to sample can still let a peak between samples creep over, so the
/// output is measured, and limited again a little lower if it isn't under the ceiling.
///
/// The look-ahead and release are starting values (TEST NEEDED).
public struct TruePeakLimiter: Sendable {
    /// The ceiling in dBTP.
    public var ceiling: Double
    public var lookahead: TimeInterval
    public var release: TimeInterval

    /// What limiting produced.
    public struct Output: Sendable {
        public var audio: AudioSamples
        /// The most it turned down at any moment, in dB.
        public var maximumReduction: Double
        /// The output's true peak, in dBTP.
        public var truePeak: Double
    }

    public init(ceiling: Double = -1, lookahead: TimeInterval = 0.002, release: TimeInterval = 0.1) {
        self.ceiling = ceiling
        self.lookahead = lookahead
        self.release = release
    }

    public func process(_ audio: AudioSamples) -> Output { process(audio, checkpoint: {}) }

    /// Stops promptly when the caller throws at a cancellation checkpoint.
    public func process(_ audio: AudioSamples, checkpoint: () throws -> Void) rethrows -> Output {
        try checkpoint()
        var target = ceiling
        var best = try limit(audio, to: target, checkpoint: checkpoint)
        for _ in 0..<4 where best.truePeak > ceiling + 0.01 {
            target -= best.truePeak - ceiling + 0.02
            best = try limit(audio, to: target, checkpoint: checkpoint)
        }
        return best
    }

    private func limit(_ audio: AudioSamples, to ceilingDecibels: Double, checkpoint: () throws -> Void) rethrows -> Output {
        try checkpoint()
        let count = audio.samples.count
        guard count > 0 else { return Output(audio: audio, maximumReduction: 0, truePeak: -.infinity) }
        let ceilingLinear = Float(pow(10, ceilingDecibels / 20))
        let envelope = try TruePeakMeter.peakEnvelope(of: audio, checkpoint: checkpoint)
        var required = [Float](repeating: 1, count: count)
        var needsLimiting = false
        for index in envelope.indices {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            required[index] = envelope[index] > ceilingLinear ? ceilingLinear / envelope[index] : 1
            if required[index] < 1 { needsLimiting = true }
        }
        guard needsLimiting else {
            return try Output(audio: audio, maximumReduction: 0, truePeak: TruePeakMeter.truePeak(of: audio, checkpoint: checkpoint))
        }

        let window = max(1, Int((lookahead * audio.sampleRate).rounded()))
        // The lowest required gain from each sample to `window` samples ahead, with a monotonic queue.
        var ahead = [Float](repeating: 1, count: count)
        var queue: [Int] = []
        var head = 0
        for index in stride(from: count - 1, through: 0, by: -1) {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            while queue.count > head, let last = queue.last, required[last] >= required[index] { queue.removeLast() }
            queue.append(index)
            while queue[head] > index + window { head += 1 }
            ahead[index] = required[queue[head]]
        }
        // A moving average over the window behind: never above `ahead` at any point it covers.
        var smoothed = [Float](repeating: 1, count: count)
        var sum: Float = 0
        for index in 0..<count {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            sum += ahead[index]
            if index > window { sum -= ahead[index - window - 1] }
            let span = min(index, window) + 1
            // Before a full window has passed, pad with unity gain, which only lowers the average less.
            smoothed[index] = min(ahead[index], (sum + Float(window + 1 - span)) / Float(window + 1))
        }
        // Release: the gain comes back up at the release time, but never above the smoothed gain.
        let releaseCoefficient = Float(release > 0 ? exp(-1 / (release * audio.sampleRate)) : 0)
        var gain: Float = 1
        var lowest: Float = 1
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            gain = min(smoothed[index], 1 - releaseCoefficient * (1 - gain))
            lowest = min(lowest, gain)
            output[index] = audio.samples[index] * gain
        }
        let limited = AudioSamples(samples: output, sampleRate: audio.sampleRate)
        return try Output(audio: limited, maximumReduction: -20 * log10(Double(lowest)), truePeak: TruePeakMeter.truePeak(of: limited, checkpoint: checkpoint))
    }
}

import Foundation

/// A feed-forward, peak-sensing compressor: above the threshold, every `ratio` dB in gives 1 dB out.
///
/// - **It reacts to peaks, not averages.** Each sample's own level goes through the gain computer, and the
///   resulting reduction is smoothed in decibels by the "smooth decoupled peak detector" of Giannoulis,
///   Massberg and Reiss, "Digital Dynamic Range Compressor Design", JAES 2012: the reduction is held at its
///   peak and lets go at the release time, then that is followed at the attack time. Holding the peak keeps
///   the reduction steady between a waveform's crests. An averaging (RMS) detector misses short transients,
///   such as plosives, which is why the first version left peaks standing.
/// - **It looks ahead.** Voice runs offline, so the gain at each moment is taken from ``lookahead`` later. The
///   gain is already coming down when a transient arrives, instead of reacting after it has passed.
/// - **Split band:** with ``bandHighPass``, the band is measured and only the band is turned down, so the rest
///   of the voice is untouched (`output = input − (1 − g)·band`). That's how the de-esser works. The band is
///   split off with a zero-phase filter, so it lines up with the input and subtracting it turns the band
///   down cleanly.
struct Compressor: Equatable, Sendable {
    /// The peak level above which it compresses, in dBFS.
    var threshold: Double
    var ratio: Double
    var attack: TimeInterval
    var release: TimeInterval
    var makeUpGain: Double = 0
    /// The most it ever turns down, in dB. Nil for no limit.
    var maximumReduction: Double?
    /// For split-band compression: the high-pass that picks out the band to measure and turn down.
    var bandHighPass: Double?
    /// How far ahead the gain looks.
    var lookahead: TimeInterval = 0

    /// What processing produced: the audio, and how many dB it was turned down at each sample.
    struct Output {
        var samples: [Float]
        var reduction: [Float]
    }

    /// The gain reduction in dB for a steady peak level: what the compressor settles at.
    func staticReduction(atLevel level: Double) -> Double {
        guard level > threshold, ratio > 1 else { return 0 }
        let reduction = (level - threshold) * (1 - 1 / ratio)
        return maximumReduction.map { min(reduction, $0) } ?? reduction
    }

    func apply(_ samples: [Float], sampleRate: Double) -> [Float] {
        process(samples, sampleRate: sampleRate).samples
    }

    func process(_ samples: [Float], sampleRate: Double) -> Output {
        let band = bandHighPass.map { Biquad.highPass(frequency: $0, sampleRate: sampleRate).applyZeroPhase(samples) }
        let measured = band ?? samples

        let attackCoefficient = Self.coefficient(attack, sampleRate)
        let releaseCoefficient = Self.coefficient(release, sampleRate)

        // The reduction each sample calls for, held at its peak with the release, then followed with the attack.
        var reduction = [Float](repeating: 0, count: samples.count)
        var held = 0.0
        var smoothed = 0.0
        for index in samples.indices {
            let level = 20 * log10(Double(abs(measured[index])) + 1e-9)
            let target = staticReduction(atLevel: level)
            held = max(target, releaseCoefficient * held + (1 - releaseCoefficient) * target)
            smoothed = attackCoefficient * smoothed + (1 - attackCoefficient) * held
            reduction[index] = Float(smoothed)
        }

        // Each sample takes the reduction from `lookahead` later, so the gain leads the transient.
        let ahead = max(0, Int((lookahead * sampleRate).rounded()))
        let makeUp = pow(10, makeUpGain / 20)
        var output = [Float](repeating: 0, count: samples.count)
        var applied = [Float](repeating: 0, count: samples.count)
        for index in samples.indices {
            let decibels = Double(reduction[min(samples.count - 1, index + ahead)])
            applied[index] = Float(decibels)
            let gain = pow(10, -decibels / 20)
            if let band {
                output[index] = Float((Double(samples[index]) - (1 - gain) * Double(band[index])) * makeUp)
            } else {
                output[index] = Float(Double(samples[index]) * gain * makeUp)
            }
        }
        return Output(samples: output, reduction: applied)
    }

    /// A one-pole smoothing coefficient for a time constant.
    private static func coefficient(_ time: TimeInterval, _ sampleRate: Double) -> Double {
        time > 0 ? exp(-1 / (time * sampleRate)) : 0
    }
}

import Foundation

/// A second-order filter, with coefficients from Robert Bristow-Johnson's "Audio EQ Cookbook".
struct Biquad: Equatable, Sendable {
    var b0: Double, b1: Double, b2: Double
    var a1: Double, a2: Double

    /// Passes everything unchanged.
    static let identity = Biquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    /// Cuts below `frequency`, 12 dB per octave.
    static func highPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let (cosine, alpha) = terms(frequency: frequency, q: q, sampleRate: sampleRate)
        return normalized(
            b0: (1 + cosine) / 2, b1: -(1 + cosine), b2: (1 + cosine) / 2,
            a0: 1 + alpha, a1: -2 * cosine, a2: 1 - alpha
        )
    }

    /// Lifts or cuts a band around `frequency` by `gain` dB.
    static func peaking(frequency: Double, gain: Double, q: Double, sampleRate: Double) -> Biquad {
        guard gain != 0 else { return .identity }
        let (cosine, alpha) = terms(frequency: frequency, q: q, sampleRate: sampleRate)
        let a = pow(10, gain / 40)
        return normalized(
            b0: 1 + alpha * a, b1: -2 * cosine, b2: 1 - alpha * a,
            a0: 1 + alpha / a, a1: -2 * cosine, a2: 1 - alpha / a
        )
    }

    /// The filter's gain in dB at a frequency.
    func gain(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // H(z) at z = e^{jw}, as complex numerator over denominator.
        let numeratorReal = b0 + b1 * cos(w) + b2 * cos(2 * w)
        let numeratorImaginary = -(b1 * sin(w) + b2 * sin(2 * w))
        let denominatorReal = 1 + a1 * cos(w) + a2 * cos(2 * w)
        let denominatorImaginary = -(a1 * sin(w) + a2 * sin(2 * w))
        let magnitude = ((numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary)
            / (denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary)).squareRoot()
        return 20 * log10(magnitude)
    }

    /// The signal through the filter.
    func apply(_ samples: [Float]) -> [Float] {
        guard self != .identity else { return samples }
        var output = [Float](repeating: 0, count: samples.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for index in samples.indices {
            let x = Double(samples[index])
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            output[index] = Float(y)
        }
        return output
    }

    /// The signal through the filter forwards, then backwards: no phase shift, and the filter's gain
    /// squared. Only possible offline, since it needs the whole signal.
    func applyZeroPhase(_ samples: [Float]) -> [Float] {
        guard self != .identity else { return samples }
        return Array(apply(Array(apply(samples).reversed())).reversed())
    }

    private static func terms(frequency: Double, q: Double, sampleRate: Double) -> (cosine: Double, alpha: Double) {
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.49) / sampleRate
        return (cos(w), sin(w) / (2 * q))
    }

    private static func normalized(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
}

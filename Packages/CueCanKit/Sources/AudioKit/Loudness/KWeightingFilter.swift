import Foundation

/// The K-weighting filter of ITU-R BS.1770: a high shelf for the head's effect, then a high-pass.
///
/// Coefficients are computed for any sample rate from the filters' analog parameters, as libebur128 does.
/// At 48 kHz they match the table in BS.1770-4 (checked in the tests).
struct KWeightingFilter {
    /// One second-order section, normalized so a0 = 1.
    struct Biquad: Equatable {
        var b0: Double, b1: Double, b2: Double
        var a1: Double, a2: Double
    }

    let shelf: Biquad
    let highPass: Biquad

    init(sampleRate: Double) {
        // Stage 1: high shelf, +4 dB above about 1.7 kHz.
        let shelfGain = 3.999843853973347
        let shelfQ = 0.7071752369554196
        let shelfFrequency = 1681.974450955533
        let k = tan(Double.pi * shelfFrequency / sampleRate)
        let vh = pow(10, shelfGain / 20)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / shelfQ + k * k
        shelf = Biquad(
            b0: (vh + vb * k / shelfQ + k * k) / a0,
            b1: 2 * (k * k - vh) / a0,
            b2: (vh - vb * k / shelfQ + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / shelfQ + k * k) / a0
        )

        // Stage 2: the RLB high-pass at about 38 Hz.
        let passQ = 0.5003270373238773
        let passFrequency = 38.13547087602444
        let kp = tan(Double.pi * passFrequency / sampleRate)
        let ap0 = 1 + kp / passQ + kp * kp
        highPass = Biquad(
            b0: 1,
            b1: -2,
            b2: 1,
            a1: 2 * (kp * kp - 1) / ap0,
            a2: (1 - kp / passQ + kp * kp) / ap0
        )
    }

    /// The signal through both stages.
    func apply(_ samples: [Float]) -> [Double] { apply(samples, checkpoint: {}) }

    func apply(_ samples: [Float], checkpoint: () throws -> Void) rethrows -> [Double] {
        try checkpoint()
        var output = [Double](repeating: 0, count: samples.count)
        var processor = Processor(filter: self)
        for index in samples.indices {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            output[index] = processor.process(samples[index])
        }
        return output
    }

    /// The same two filters, retaining only their previous two samples for a streaming measurement.
    struct Processor {
        let filter: KWeightingFilter
        private var s1 = (x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0)
        private var s2 = (x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0)

        init(filter: KWeightingFilter) { self.filter = filter }

        mutating func process(_ sample: Float) -> Double {
            let shelf = filter.shelf, highPass = filter.highPass
            let x = Double(sample)
            let y = shelf.b0 * x + shelf.b1 * s1.x1 + shelf.b2 * s1.x2 - shelf.a1 * s1.y1 - shelf.a2 * s1.y2
            s1 = (x, s1.x1, y, s1.y1)
            let z = highPass.b0 * y + highPass.b1 * s2.x1 + highPass.b2 * s2.x2 - highPass.a1 * s2.y1 - highPass.a2 * s2.y2
            s2 = (y, s2.x1, z, s2.y1)
            return z
        }
    }
}

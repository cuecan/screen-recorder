import Foundation
import Testing
@testable import AudioKit

struct StreamingLoudnessTests {
    @Test(arguments: [48_000.0, 44_100.0, 16_000.0, 11_025.0, 10_001.0])
    func boundedMeasurementMatchesTheFullArrayReferenceExactly(sampleRate: Double) {
        let samples = (0..<Int(sampleRate * 3.17)).map { index -> Float in
            let time = Double(index) / sampleRate
            let level = time < 0.5 ? 0.001 : time < 1.8 ? 0.2 : time < 2.5 ? 0 : 0.08
            return Float(level * (sin(2 * .pi * 217 * time) + 0.3 * sin(2 * .pi * 2_345 * time)))
        }
        let audio = AudioSamples(samples: samples, sampleRate: sampleRate)
        let block = Int((0.4 * sampleRate).rounded()), step = Int((0.1 * sampleRate).rounded())
        let weighted = KWeightingFilter(sampleRate: sampleRate).apply(samples)
        var cumulative = [Double](repeating: 0, count: weighted.count + 1)
        for index in weighted.indices { cumulative[index + 1] = cumulative[index] + weighted[index] * weighted[index] }
        let powers = stride(from: 0, through: weighted.count - block, by: step).map {
            (cumulative[$0 + block] - cumulative[$0]) / Double(block)
        }
        let aboveAbsolute = powers.filter { $0 > LoudnessMeter.power(forLoudness: -70) }
        let relative = aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count) * pow(10, -1)
        let gated = aboveAbsolute.filter { $0 > relative }
        let expected = LoudnessMeter.loudness(forPower: gated.reduce(0, +) / Double(gated.count))
        #expect(LoudnessMeter.integratedLoudness(of: audio) == expected)
    }
}

import Foundation
@testable import AudioKit

/// Synthetic test signals. They exist to test the code against known answers, not to stand in for
/// recordings.
enum Signal {
    /// A sine wave with a peak amplitude given in dBFS.
    static func sine(
        frequency: Double = 997,
        peakDecibels: Double,
        duration: TimeInterval,
        sampleRate: Double = 48_000
    ) -> [Float] {
        let amplitude = pow(10, peakDecibels / 20)
        let count = Int(duration * sampleRate)
        return (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    static func silence(duration: TimeInterval, sampleRate: Double = 48_000) -> [Float] {
        [Float](repeating: 0, count: Int(duration * sampleRate))
    }
}

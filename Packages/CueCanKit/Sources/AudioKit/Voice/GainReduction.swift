import Foundation

/// How hard a compressor worked: how many dB it turned the audio down.
public struct GainReduction: Sendable, Equatable, Codable {
    /// The average reduction while it was working, in dB: over the moments it turned down by more than
    /// ``workingThreshold``.
    public var averageWhileWorking: Double
    /// The most it turned down at any moment, in dB.
    public var maximum: Double
    /// The share of the time it was working, from 0 to 1.
    public var shareOfTime: Double

    /// Reductions smaller than this, in dB, count as not working.
    public static let workingThreshold: Float = 0.5

    init(_ reduction: [Float]) {
        var sum = 0.0
        var working = 0
        var maximum: Float = 0
        for value in reduction {
            maximum = max(maximum, value)
            if value > Self.workingThreshold {
                sum += Double(value)
                working += 1
            }
        }
        averageWhileWorking = working > 0 ? sum / Double(working) : 0
        self.maximum = Double(maximum)
        shareOfTime = reduction.isEmpty ? 0 : Double(working) / Double(reduction.count)
    }
}

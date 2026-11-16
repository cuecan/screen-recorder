import Foundation

/// Cuts a stream of samples into windows of a fixed length and measures each one's peak and RMS.
///
/// It's fed the same buffers that go to the mic file, so the waveform shows what's written, not just what
/// the device hears (docs/decisions.md, 18).
public struct LevelAnalyzer: Sendable {
    /// About every 20 ms: 250 values for the widget's 5 seconds.
    public static let windowDuration = 0.02

    public let samplesPerWindow: Int
    private var count = 0
    private var peak: Float = 0
    private var sumOfSquares: Double = 0

    public init(sampleRate: Double, windowDuration: Double = Self.windowDuration) {
        samplesPerWindow = max(1, Int((sampleRate * windowDuration).rounded()))
    }

    /// Adds samples and returns every window they completed.
    public mutating func append(_ samples: UnsafeBufferPointer<Float>) -> [LevelSample] {
        var finished: [LevelSample] = []
        for sample in samples {
            let size = abs(sample)
            if size > peak { peak = size }
            sumOfSquares += Double(sample) * Double(sample)
            count += 1
            if count == samplesPerWindow {
                finished.append(LevelSample(peak: min(peak, 1), rms: Float((sumOfSquares / Double(count)).squareRoot())))
                count = 0
                peak = 0
                sumOfSquares = 0
            }
        }
        return finished
    }

    public mutating func append(_ samples: [Float]) -> [LevelSample] {
        samples.withUnsafeBufferPointer { append($0) }
    }
}

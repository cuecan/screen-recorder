import Foundation

/// The peak levels of a voice's speech, for setting a compressor's threshold by how much of the speech it
/// should touch, rather than by a fixed level that would mean different things on a quiet and a hot mic.
enum SpeechPeaks {
    /// How long each measured stretch is.
    static let block: TimeInterval = 0.05
    /// Stretches more than this far below the loudest speech are pauses and room noise, and don't count.
    static let speechRange = 30.0

    /// The peak level in dBFS that `percentile` of the speech stretches stay under. A compressor with its
    /// threshold here touches the loudest `100 − percentile` percent of them. Nil if there's no speech.
    static func threshold(_ samples: [Float], sampleRate: Double, percentile: Double) -> Double? {
        let peaks = speechBlockPeaks(samples, sampleRate: sampleRate)
        guard !peaks.isEmpty else { return nil }
        let sorted = peaks.sorted()
        let position = Int((Double(sorted.count - 1) * min(100, max(0, percentile)) / 100).rounded())
        return sorted[position]
    }

    /// The peak level of each 50 ms stretch that holds speech, in dBFS.
    static func speechBlockPeaks(_ samples: [Float], sampleRate: Double) -> [Double] {
        let length = max(1, Int(block * sampleRate))
        let blocks = samples.count / length
        guard blocks > 0 else { return [] }
        var levels: [(peak: Double, rms: Double)] = []
        levels.reserveCapacity(blocks)
        for index in 0..<blocks {
            var peak: Float = 0
            var sum: Double = 0
            for sample in samples[(index * length)..<((index + 1) * length)] {
                peak = max(peak, abs(sample))
                sum += Double(sample) * Double(sample)
            }
            levels.append((20 * log10(Double(peak) + 1e-9), 10 * log10(sum / Double(length) + 1e-18)))
        }
        // Speech is what's within `speechRange` of the loud end of the recording.
        let loudest = levels.map(\.rms).sorted()[Int(Double(blocks - 1) * 0.95)]
        return levels.filter { $0.rms > loudest - speechRange }.map(\.peak)
    }
}

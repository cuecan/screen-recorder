import Foundation

/// Keeps a continuous audio file in step with the recording's clock.
///
/// A WAV file has no timestamps: sample n plays at n ÷ rate. So each buffer is placed where its own time
/// says, not just after the last one. If the mic went quiet on the clock (unplugged and back, a device
/// switch, a dropped buffer), the gap is filled with silence; if a buffer overlaps what's written, its
/// overlap is dropped. Small differences are timestamp jitter and are left alone, so steady audio is never
/// nudged.
public struct SamplePlacement: Sendable, Equatable {
    public let sampleRate: Double
    /// Differences up to this many seconds are jitter. A starting value: about half a mic buffer.
    public let tolerance: TimeInterval
    /// Where the file's first sample is on the recording's clock.
    public private(set) var start: TimeInterval?
    /// How many samples are in the file so far.
    public private(set) var written = 0

    public init(sampleRate: Double, tolerance: TimeInterval = 0.01) {
        self.sampleRate = sampleRate
        self.tolerance = tolerance
    }

    /// What to do with a buffer of `count` samples whose first sample is at `time`: how much silence to
    /// write before it, and how many of its first samples to skip.
    public mutating func place(count: Int, at time: TimeInterval) -> (silence: Int, skip: Int) {
        guard let start else {
            start = time
            written = count
            return (0, 0)
        }
        let expected = Int(((time - start) * sampleRate).rounded())
        let difference = expected - written
        let slack = Int(tolerance * sampleRate)
        var silence = 0
        var skip = 0
        if difference > slack {
            silence = difference
        } else if difference < -slack {
            skip = min(count, -difference)
        }
        written += silence + count - skip
        return (silence, skip)
    }
}

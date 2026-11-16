import AVFoundation
import Foundation
import ProjectKit

/// Mono audio in memory, as 32-bit float samples at a sample rate.
///
/// Voice cleanup, transcription and silence detection all work on one channel. A recording's mic is
/// mono already, and imported stereo is mixed down when read (``AudioFileReader``).
public struct AudioSamples: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: TimeInterval {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }

    /// The sample index for a time, clamped to the audio.
    public func index(at time: TimeInterval) -> Int {
        let frame = (time * sampleRate).rounded()
        guard frame > 0 else { return 0 }
        guard frame < Double(samples.count) else { return samples.count }
        return Int(frame)
    }

    /// The samples within a time range, clamped to the audio.
    public func slice(_ range: TimeRange) -> AudioSamples {
        let start = index(at: range.start)
        let end = max(start, index(at: range.end))
        return AudioSamples(samples: Array(samples[start..<end]), sampleRate: sampleRate)
    }

    /// The largest absolute sample value, from 0 to 1 for audio that doesn't clip.
    public var peak: Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// The same audio at another sample rate, converted with `AVAudioConverter`.
    public func resampled(to targetRate: Double) throws -> AudioSamples {
        guard targetRate.isFinite, targetRate > 0, sampleRate.isFinite, sampleRate > 0 else {
            throw AudioKitError.conversionFailed("Sample rates must be finite and greater than zero.")
        }
        guard targetRate != sampleRate else { return self }
        guard !samples.isEmpty else { return AudioSamples(samples: [], sampleRate: targetRate) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 1) else {
            throw AudioKitError.conversionFailed("Couldn't describe mono audio at \(targetRate) Hz.")
        }
        let output = try pcmBuffer(in: format)
        let count = Int(output.frameLength)
        let result = output.floatChannelData.map { Array(UnsafeBufferPointer(start: $0[0], count: count)) } ?? []
        return AudioSamples(samples: result, sampleRate: targetRate)
    }

    /// The samples with a gain in decibels applied.
    public func applyingGain(decibels: Double) -> AudioSamples { applyingGain(decibels: decibels, checkpoint: {}) }

    /// Applies gain with cancellation checkpoints between bounded runs of samples.
    public func applyingGain(decibels: Double, checkpoint: () throws -> Void) rethrows -> AudioSamples {
        try checkpoint()
        let factor = Float(pow(10, decibels / 20))
        var output = [Float](repeating: 0, count: samples.count)
        for index in samples.indices {
            if index.isMultiple(of: 16_384) { try checkpoint() }
            output[index] = samples[index] * factor
        }
        return AudioSamples(samples: output, sampleRate: sampleRate)
    }
}

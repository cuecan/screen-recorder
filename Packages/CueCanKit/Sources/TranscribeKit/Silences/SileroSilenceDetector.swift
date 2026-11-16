import AudioKit
internal import FluidAudio
import Foundation
import ProjectKit

/// Finds silences as the gaps between the speech Silero VAD finds, through FluidAudio on Core ML.
///
/// FluidAudio's Silero scores audio in 256 ms blocks, too coarse for cut points in the bake-off
/// (docs/decisions.md, 40). It stays as a bake-off candidate; ``EnergySilenceDetector`` supplies the
/// silences used for editing.
///
/// The model is about 1 MB, downloaded on first use into FluidAudio's cache.
public final class SileroSilenceDetector: SilenceDetector {
    public let id = "silero"
    /// FluidAudio's default speech threshold.
    public static let defaultThreshold = VadConfig.default.defaultThreshold
    /// How sure Silero has to be that a block is speech, from 0 to 1 (TEST NEEDED). Speech ends when it drops
    /// 0.15 below this.
    public let threshold: Float
    /// Gaps shorter than this are pauses within speech, not silences. A starting value (TEST NEEDED).
    public let minimumSilence: TimeInterval

    private var manager: VadManager?

    public init(threshold: Float = SileroSilenceDetector.defaultThreshold, minimumSilence: TimeInterval = 0.2) {
        self.threshold = threshold
        self.minimumSilence = minimumSilence
    }

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {
        do {
            manager = try await VadManager(config: VadConfig(defaultThreshold: threshold))
        } catch {
            throw AudioKitError.modelFailed("Silero VAD", "It couldn't load: \(error.localizedDescription)")
        }
    }

    public func unload() {
        manager = nil
    }

    public func silences(in audio: AudioSamples) async throws -> [TimeRange] {
        try await speech(in: audio).silences
    }

    /// The speech Silero finds, and the silences between it.
    func speech(in audio: AudioSamples) async throws -> (speech: [TimeRange], silences: [TimeRange]) {
        guard let manager else { throw AudioKitError.modelFailed("Silero VAD", "It isn't loaded.") }
        let input = try audio.resampled(to: Double(VadManager.sampleRate))
        // No padding and no length limit: the speech as Silero hears it, so the gaps are the real silences.
        let segmentation = VadSegmentationConfig(
            minSpeechDuration: 0.1,
            minSilenceDuration: minimumSilence,
            maxSpeechDuration: .infinity,
            speechPadding: 0
        )
        let segments: [VadSegment]
        do {
            segments = try await manager.segmentSpeech(input.samples, config: segmentation)
        } catch {
            throw AudioKitError.modelFailed("Silero VAD", error.localizedDescription)
        }
        let speech = segments.map { TimeRange(start: $0.startTime, end: min($0.endTime, audio.duration)) }
        return (speech, SpeechGaps.silences(between: speech, duration: audio.duration, minimum: minimumSilence))
    }
}

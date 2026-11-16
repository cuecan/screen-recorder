import AudioKit
internal import FluidAudio
import Foundation

/// NVIDIA's Nemotron 3.5 Transcribe Lite through FluidAudio: the encoder and the timestamp head of Nemotron
/// 3.5 Transcribe, without its language model. A bake-off candidate for word timing (docs/bakeoff-findings.md), not part of the app.
///
/// - Its head places word starts on a 40 ms grid, half Parakeet's 80 ms. NVIDIA trained it to time the full
///   model's words, and FluidAudio's notes say that read by itself it's much less accurate than the full
///   model, so its words are for comparison and its times are the point.
/// - It gives each word a start and no end. A word's end here is the next word's start, and the last word
///   ends with the audio, so only the starts mean anything.
public final class NemotronLiteEngine: TranscriptionEngine {
    public let id = "nemotron-lite"
    public let displayName = "Nemotron 3.5 Transcribe Lite"
    public let weightsDescription = "Nemotron 3.5 Transcribe Lite for Core ML, through FluidAudio (about 1.3 GB)"
    /// FluidAudio windows long audio itself.
    public let maximumChunkDuration: TimeInterval? = nil
    private var manager: NemotronTranscribeLiteManager?

    public init() {}

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {
        guard manager == nil else { return }
        let loaded = try await NemotronTranscribeLiteManager.load { update in
            progress("\(Int(update.fractionCompleted * 100))%")
        }
        try await loaded.warmup()
        manager = loaded
    }

    public func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord] {
        guard let manager else { throw AudioKitError.modelFailed(displayName, "It isn't loaded.") }
        let input = try audio.resampled(to: Double(NemotronTranscribeLiteConfig.sampleRate))
        guard !input.samples.isEmpty else { return [] }
        let result: NemotronTranscribeLiteResult
        do {
            result = try await manager.transcribe(audio: input.samples)
        } catch {
            throw AudioKitError.modelFailed(displayName, error.localizedDescription)
        }
        return Self.words(result.words.map { ($0.text, $0.start) }, duration: result.durationSeconds)
    }

    public func unload() { manager = nil }

    /// Words with starts only, given ends: each ends where the next starts, and the last with the audio.
    static func words(_ starts: [(text: String, start: Double)], duration: Double) -> [TimedWord] {
        starts.enumerated().map { index, word in
            let next = index + 1 < starts.count ? starts[index + 1].start : duration
            return TimedWord(text: word.text, start: word.start, end: max(word.start, next))
        }
    }
}

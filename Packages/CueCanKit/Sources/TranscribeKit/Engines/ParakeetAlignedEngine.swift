import AudioKit
import Foundation
import ProjectKit

/// Parakeet's words, placed again by forced alignment: the transcript Parakeet TDT wrote is aligned, whole,
/// against the audio with Parakeet CTC 110M, the model that already times a fixed word
/// (``CTCWordAligner``; docs/decisions.md, 69). A bake-off candidate for word timing that needs no new
/// download (docs/bakeoff-findings.md), not part of the app.
///
/// The whole recording is aligned in one pass, which is fine for a bake-off clip and untried on a long take.
public final class ParakeetAlignedEngine: TranscriptionEngine {
    public let id = "parakeet-aligned"
    public let displayName = "Parakeet TDT v3, aligned with Parakeet CTC"
    public let weightsDescription = "Parakeet TDT v3 and Parakeet CTC 110M for Core ML, through FluidAudio"
    public let maximumChunkDuration: TimeInterval? = nil
    private let parakeet = ParakeetEngine(version: .v3)
    private let aligner = CTCWordAligner()

    public init() {}

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {
        try await parakeet.load(progress: progress)
        try await aligner.load()
    }

    public func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord] {
        let words = try await parakeet.transcribe(audio, language: language)
        guard !words.isEmpty else { return [] }
        let text = words.map(\.text).joined(separator: " ")
        guard let aligned = try await aligner.align(text, in: audio, startsAt: 0), aligned.words.count == words.count else {
            // Text the aligner can't place keeps Parakeet's own times, so the comparison shows it as no change.
            return words
        }
        return zip(words, aligned.words).map { word, placed in
            TimedWord(text: word.text, start: placed.start, end: placed.end, confidence: word.confidence)
        }
    }

    public func unload() { parakeet.unload() }
}

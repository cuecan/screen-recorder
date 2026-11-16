import AudioKit
import Foundation
import ProjectKit

/// Parakeet's words with the app's timing steps applied, for measuring them in the bake-off the way a take's
/// processing applies them (docs/bakeoff-findings.md): fitted to the audio (``WordFitter``, decision 74),
/// placed by the timing model (``WordTimer``, decision 95), or both, which is what processing does.
public final class ParakeetTimingEngine: TranscriptionEngine {
    public enum Steps: String, Sendable, CaseIterable {
        /// Fitted to the audio only: what processing did before the timing model.
        case fitted
        /// Placed by the timing model, and nothing after.
        case timed
        /// Placed by the timing model, then fitted to the audio as Parakeet's own times are.
        case timedAndFitted = "timed-fitted"
        /// Placed by the timing model, then only kept out of silences: what processing does.
        case timedAndClamped = "timed-clamped"
    }

    public let steps: Steps
    public var id: String { "parakeet-\(steps.rawValue)" }
    public var displayName: String { "Parakeet TDT v3, \(steps.rawValue)" }
    public let weightsDescription = "Parakeet TDT v3 through FluidAudio, and CueCan's timing model for the timed ones"
    public let maximumChunkDuration: TimeInterval? = nil
    private let parakeet = ParakeetEngine(version: .v3)
    private var timer: WordTimer?

    public init(steps: Steps) { self.steps = steps }

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {
        try await parakeet.load(progress: progress)
        if steps != .fitted, timer == nil { timer = try WordTimer() }
    }

    public func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord] {
        var words = try await parakeet.transcribe(audio, language: language)
        if let timer {
            words = WordRetimer.retime(words, starts: try timer.starts(of: words, in: audio))
        }
        guard steps != .timed else { return words }
        let settings = steps == .timedAndClamped ? WordFitter.Settings.afterTiming : WordFitter.Settings()
        return WordFitter.fit(words, to: EnergySilenceDetector().analyze(audio), settings: settings)
    }

    public func unload() {
        parakeet.unload()
        timer = nil
    }
}

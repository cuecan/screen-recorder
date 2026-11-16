import AudioKit
import CoreMedia
import Foundation
import ProjectKit
import Speech

/// Finds silences as the gaps between the speech Apple's `SpeechDetector` finds, in macOS 26's Speech
/// framework. It's a voice activity model built into macOS, with nothing to download. Unlike
/// ``EnergySilenceDetector`` it can tell breaths and room noise from speech, but its edges come from a model
/// rather than the waveform. Which detector cuts better is for the ear (docs/bakeoff-findings.md).
///
/// **Measured on macOS 27.2, it reports nothing for audio analyzed after recording.** It sent no results at
/// any sensitivity, with a regular or a progressive transcriber, on synthetic speech or a real recording, so
/// it appears to gate the transcriber internally rather than report. Rather than read that as "the whole
/// file is silence", which would put every cut in the wrong place, ``silences(in:)`` throws. It's kept for
/// the bake-off, to check again on later versions of macOS.
///
/// Two of its requirements stop the program rather than throwing (macOS 27.2), so both are met here:
/// - It only runs in an analysis that also has a transcriber module, so one runs alongside, and its words
///   are drained and discarded. In the app it can share the pass that gives SpeechAnalyzer's reading.
/// - It only takes the samples `SpeechAnalyzer` says it can, 16-bit integers here, so audio goes through
///   ``AppleSpeechAnalysis``, which converts to that format.
public final class SpeechDetectorSilenceDetector: SilenceDetector {
    public let id = "apple-speechdetector"
    public let sensitivity: SpeechDetector.SensitivityLevel
    /// Gaps shorter than this are pauses within speech, not silences. A starting value (TEST NEEDED).
    public let minimumSilence: TimeInterval

    public init(sensitivity: SpeechDetector.SensitivityLevel = .medium, minimumSilence: TimeInterval = 0.2) {
        self.sensitivity = sensitivity
        self.minimumSilence = minimumSilence
    }

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {}
    public func unload() {}

    public func silences(in audio: AudioSamples) async throws -> [TimeRange] {
        let transcriber = SpeechTranscriber(locale: try await AppleSpeechAnalysis.locale(for: nil), preset: .transcription)
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: sensitivity), reportResults: true)
        async let collected = Self.speech(in: detector.results)
        async let drained: Void = Self.drain(transcriber.results)
        try await AppleSpeechAnalysis.analyze(audio, with: [transcriber, detector])
        try await drained
        return SpeechGaps.silences(between: try await collected, duration: audio.duration, minimum: minimumSilence)
    }

    private static func drain(_ results: some AsyncSequence<SpeechTranscriber.Result, any Error>) async throws {
        for try await _ in results {}
    }

    private static func speech(in results: some AsyncSequence<SpeechDetector.Result, any Error>) async throws -> [TimeRange] {
        var speech: [TimeRange] = []
        var reported = 0
        for try await result in results {
            reported += 1
            guard result.speechDetected else { continue }
            let start = result.range.start.seconds
            speech.append(TimeRange(start: start, end: start + result.range.duration.seconds))
        }
        guard reported > 0 else {
            throw AudioKitError.modelFailed(
                "Apple SpeechDetector",
                "It reported no speech or silence at all, which it does for audio analyzed after recording on this version of macOS."
            )
        }
        return speech
    }
}

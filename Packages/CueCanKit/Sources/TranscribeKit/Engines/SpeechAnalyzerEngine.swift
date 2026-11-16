import AudioKit
import CoreMedia
import Foundation
import Speech

/// Apple's `SpeechAnalyzer` with `SpeechTranscriber`: nothing to download with the app, since macOS installs
/// the language model itself. It gives the second reading where it and Parakeet disagree (docs/decisions.md,
/// 39). It's accurate on clean speech, but tidies away repeats and fillers, and its `SpeechTranscriber`
/// ignores vocabulary hints (docs/bakeoff-findings.md).
///
/// Word times come from the `audioTimeRange` attribute on each run of the result's text. A run that holds
/// more than one word has its time shared out by length.
public final class SpeechAnalyzerEngine: TranscriptionEngine {
    public let id = "apple-speechanalyzer"
    public let displayName = "Apple SpeechAnalyzer"
    public let weightsDescription = "macOS speech assets for the language (installed by the system)"
    /// SpeechAnalyzer is built for long-form audio, so it gets the whole recording.
    public let maximumChunkDuration: TimeInterval? = nil

    public init() {}

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {}
    public func unload() {}

    public func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord] {
        let transcriber = SpeechTranscriber(
            locale: try await AppleSpeechAnalysis.locale(for: language),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        async let collected = Self.collect(transcriber.results)
        try await AppleSpeechAnalysis.analyze(audio, with: [transcriber])
        return try await collected
    }

    private static func collect(
        _ results: some AsyncSequence<SpeechTranscriber.Result, any Error>
    ) async throws -> [TimedWord] {
        var words: [TimedWord] = []
        for try await result in results where result.isFinal {
            words.append(contentsOf: Self.words(in: result.text))
        }
        return words
    }

    /// The words of one result, each timed from the run it came in.
    static func words(in text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let runText = String(text[run.range].characters)
            let pieces = runText.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !pieces.isEmpty else { continue }
            let start = range.start.seconds
            let duration = range.duration.seconds
            let totalLength = Double(pieces.reduce(0) { $0 + $1.count })
            var cursor = start
            for piece in pieces {
                let share = totalLength > 0 ? duration * Double(piece.count) / totalLength : duration / Double(pieces.count)
                words.append(TimedWord(text: piece, start: cursor, end: cursor + share, confidence: run.transcriptionConfidence))
                cursor += share
            }
        }
        return words
    }
}

import AudioKit
import Foundation
import ProjectKit

/// Runs an engine over a whole recording: splits it at silences into pieces the engine can take, then
/// puts the words back on the recording's timeline.
public enum Transcriber {
    public static func transcribe(
        _ audio: AudioSamples,
        with engine: some TranscriptionEngine,
        silences: [TimeRange],
        language: String?,
        progress: @Sendable (String) -> Void = { _ in }
    ) async throws -> [TimedWord] {
        let chunks = engine.maximumChunkDuration.map {
            AudioChunker.chunks(duration: audio.duration, silences: silences, maximumDuration: $0)
        } ?? [TimeRange(start: 0, end: audio.duration)]

        var words: [TimedWord] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            if chunks.count > 1 {
                progress("Piece \(index + 1) of \(chunks.count)")
            }
            let piece = chunks.count == 1 ? audio : audio.slice(chunk)
            let pieceWords = try await engine.transcribe(piece, language: language)
            words.append(contentsOf: pieceWords.map { $0.offset(by: chunk.start) })
        }
        return words
    }
}

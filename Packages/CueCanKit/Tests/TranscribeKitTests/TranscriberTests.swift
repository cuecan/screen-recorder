import AudioKit
import CoreMedia
import Foundation
import ProjectKit
import Testing
@testable import TranscribeKit

/// Reports one word per piece it's handed, at a fixed time within the piece, so the test can check how
/// pieces were cut and offset.
final class PieceRecordingEngine: TranscriptionEngine {
    let id = "stub"
    let displayName = "Stub"
    let weightsDescription = "none"
    let maximumChunkDuration: TimeInterval?
    private(set) var pieceDurations: [TimeInterval] = []

    init(maximumChunkDuration: TimeInterval?) {
        self.maximumChunkDuration = maximumChunkDuration
    }

    func load(progress: @escaping @Sendable (String) -> Void) async throws {}
    func unload() {}

    func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord] {
        pieceDurations.append(audio.duration)
        return [TimedWord(text: "piece\(pieceDurations.count)", start: 0.25, end: 0.5)]
    }
}

@Suite struct TranscriberTests {
    let audio = AudioSamples(samples: [Float](repeating: 0, count: 50 * 100), sampleRate: 100)

    @Test func longAudioIsTranscribedInPiecesAndPutBackInPlace() async throws {
        let engine = PieceRecordingEngine(maximumChunkDuration: 30)
        let words = try await Transcriber.transcribe(
            audio, with: engine, silences: [TimeRange(start: 22, end: 25)], language: "en"
        )
        #expect(engine.pieceDurations == [23.5, 26.5])
        #expect(words.map(\.text) == ["piece1", "piece2"])
        #expect(words.map(\.start) == [0.25, 23.75], "Each piece's words are shifted to where the piece starts.")
    }

    @Test func enginesThatTakeAnyLengthGetTheWholeRecording() async throws {
        let engine = PieceRecordingEngine(maximumChunkDuration: nil)
        _ = try await Transcriber.transcribe(audio, with: engine, silences: [], language: nil)
        #expect(engine.pieceDurations == [50])
    }
}

@Suite struct SpeechAnalyzerParsingTests {
    func run(_ text: String, start: Double, duration: Double) -> AttributedString {
        var piece = AttributedString(text)
        piece.audioTimeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        return piece
    }

    @Test func eachTimedRunIsAWord() {
        var text = run("Hello", start: 1, duration: 0.5)
        text.append(AttributedString(" "))
        text.append(run("there.", start: 1.6, duration: 0.4))
        let words = SpeechAnalyzerEngine.words(in: text)
        #expect(words.map(\.text) == ["Hello", "there."])
        #expect(abs(words[0].start - 1) < 1e-3 && abs(words[0].end - 1.5) < 1e-3)
        #expect(abs(words[1].start - 1.6) < 1e-3 && abs(words[1].end - 2.0) < 1e-3)
    }

    @Test func aRunWithSeveralWordsSharesItsTimeByLength() {
        let words = SpeechAnalyzerEngine.words(in: run("ab abcd", start: 0, duration: 0.6))
        #expect(words.map(\.text) == ["ab", "abcd"])
        #expect(abs(words[0].end - 0.2) < 1e-6)
        #expect(abs(words[1].start - 0.2) < 1e-6 && abs(words[1].end - 0.6) < 1e-6)
    }
}

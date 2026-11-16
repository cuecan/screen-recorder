import Foundation
import Testing
@testable import AudioKit

@Suite struct AudioReviewRegressionTests {
    @Test func aShortClipStillRespectsTheExportPeakCeiling() {
        let audio = AudioSamples(samples: [Float](repeating: 2, count: 480), sampleRate: 48_000)
        let result = LoudnessStage.process(audio)
        #expect(!result.inputLoudness.isFinite)
        #expect(result.truePeak <= -0.99)
        #expect(result.audio.samples.count == audio.samples.count)
    }

    @Test func sampleIndicesClampBeforeConvertingToAnInteger() {
        let audio = AudioSamples(samples: [0, 1, 0], sampleRate: 48_000)
        #expect(audio.index(at: .infinity) == 3)
        #expect(audio.index(at: -.infinity) == 0)
        #expect(audio.index(at: .greatestFiniteMagnitude) == 3)
        #expect(audio.index(at: .nan) == 0)
    }

    @Test func stalledRenderingFailsAndProgressResetsItsRetryCount() throws {
        var progress = OfflineRenderProgress(totalFrames: 10, renderer: "test", maximumRetries: 2)
        try progress.advance(by: 0)
        try progress.advance(by: 0)
        try progress.advance(by: 5)
        try progress.advance(by: 0)
        try progress.advance(by: 0)
        #expect(throws: AudioKitError.self) { try progress.advance(by: 0) }
        try progress.advance(by: 5)
        #expect(progress.isFinished)
    }

    @Test func cleanupAcceptsEmptyAudioAndHonoursCancellation() async throws {
        let model = SoundIsolationCleanup()
        let empty = AudioSamples(samples: [], sampleRate: 48_000)
        #expect(try await model.clean(empty) == empty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await model.clean(empty)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

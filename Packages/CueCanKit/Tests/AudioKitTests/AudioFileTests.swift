import Foundation
import Testing
@testable import AudioKit

@Suite struct AudioFileTests {
    func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AudioKitTests-\(UUID().uuidString)/\(name)")
    }

    @Test func float32WAVRoundTripsExactly() async throws {
        let audio = AudioSamples(samples: Signal.sine(frequency: 440, peakDecibels: -3, duration: 1.5), sampleRate: 48_000)
        let url = temporaryURL("tone.wav")
        try AudioFileWriter.writeWAV(audio, to: url, encoding: .float32)

        let read = try await AudioFileReader.readMono(url, sampleRate: 48_000)
        #expect(read.samples.count == audio.samples.count)
        let largestError = zip(read.samples, audio.samples).map { abs($0 - $1) }.max() ?? 0
        #expect(largestError < 1e-6)
    }

    @Test func int24WAVIsCloseAndReadsAtAnotherRate() async throws {
        let audio = AudioSamples(samples: Signal.sine(frequency: 440, peakDecibels: -6, duration: 2), sampleRate: 48_000)
        let url = temporaryURL("tone24.wav")
        try AudioFileWriter.writeWAV(audio, to: url, encoding: .int24)

        let tracks = try await AudioFileReader.audioTracks(in: url)
        #expect(tracks.count == 1)
        #expect(tracks.first?.channels == 1)
        #expect(tracks.first?.sampleRate == 48_000)

        let read = try await AudioFileReader.readMono(url, sampleRate: 16_000)
        #expect(abs(read.duration - 2) < 0.01)
        #expect(abs(LoudnessMeter.integratedLoudness(of: read) - LoudnessMeter.integratedLoudness(of: audio)) < 0.1)
    }

    @Test func missingTrackIsReported() async throws {
        let audio = AudioSamples(samples: Signal.silence(duration: 0.5), sampleRate: 48_000)
        let url = temporaryURL("silence.wav")
        try AudioFileWriter.writeWAV(audio, to: url)
        await #expect(throws: AudioKitError.trackOutOfRange(url, requested: 2, available: 1)) {
            try await AudioFileReader.readMono(url, track: 2)
        }
    }

    @Test func unreadableFileIsReported() async throws {
        let url = temporaryURL("not-audio.wav")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not audio".utf8).write(to: url)
        await #expect(throws: AudioKitError.self) { try await AudioFileReader.readMono(url) }
    }
}

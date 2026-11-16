import AudioKit
import Foundation
import ProjectKit
import Testing
@testable import TranscribeKit

/// Synthetic signals with known quiet stretches, to test the detector's logic, not its judgment on speech.
enum SyntheticSpeech {
    /// Deterministic white noise at a level in dBFS RMS, so tests never vary.
    static func noise(duration: TimeInterval, rmsDecibels: Double, sampleRate: Double, seed: UInt64) -> [Float] {
        var state = seed
        let amplitude = pow(10, rmsDecibels / 20) * sqrt(3)  // uniform in ±a has RMS a/√3
        return (0..<Int(duration * sampleRate)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(state >> 11) / Double(1 << 53)
            return Float(amplitude * (unit * 2 - 1))
        }
    }

    static func tone(duration: TimeInterval, peakDecibels: Double, sampleRate: Double) -> [Float] {
        let amplitude = pow(10, peakDecibels / 20)
        return (0..<Int(duration * sampleRate)).map { Float(amplitude * sin(2 * .pi * 220 * Double($0) / sampleRate)) }
    }

    /// Alternating quiet and loud stretches over a noise floor. Returns the audio and where the quiet
    /// stretches are.
    static func make(
        _ pattern: [(quiet: Bool, duration: TimeInterval)],
        floor: Double = -60,
        sampleRate: Double = 16_000
    ) -> (AudioSamples, [TimeRange]) {
        var samples: [Float] = []
        var quiet: [TimeRange] = []
        var cursor = 0.0
        for (index, part) in pattern.enumerated() {
            var piece = noise(duration: part.duration, rmsDecibels: floor, sampleRate: sampleRate, seed: UInt64(index + 1))
            if !part.quiet {
                let tone = tone(duration: part.duration, peakDecibels: -12, sampleRate: sampleRate)
                piece = zip(piece, tone).map(+)
            } else {
                quiet.append(TimeRange(start: cursor, end: cursor + part.duration))
            }
            samples += piece
            cursor += part.duration
        }
        return (AudioSamples(samples: samples, sampleRate: sampleRate), quiet)
    }
}

@Suite struct EnergySilenceDetectorTests {
    let detector = EnergySilenceDetector()

    func expectRanges(_ actual: [TimeRange], _ expected: [TimeRange], tolerance: Double = 0.021, sourceLocation: SourceLocation = #_sourceLocation) {
        let matches = actual.count == expected.count
            && zip(actual, expected).allSatisfy { abs($0.start - $1.start) <= tolerance && abs($0.end - $1.end) <= tolerance }
        #expect(matches, "Expected \(expected), got \(actual)", sourceLocation: sourceLocation)
    }

    @Test func findsQuietStretchesBetweenSounds() {
        let (audio, _) = SyntheticSpeech.make([
            (true, 0.5), (false, 1.0), (true, 0.4), (false, 1.0), (true, 0.1), (false, 1.0), (true, 0.6),
        ])
        // The 0.1 s gap is shorter than the minimum silence, so it's a pause within speech.
        expectRanges(detector.detect(in: audio), [
            TimeRange(start: 0, end: 0.5),
            TimeRange(start: 1.5, end: 1.9),
            TimeRange(start: 4.0, end: 4.6),
        ])
    }

    @Test func adaptsToANoisyRoom() {
        let (audio, quiet) = SyntheticSpeech.make([(false, 1.0), (true, 0.5), (false, 1.0), (true, 0.5), (false, 1.0)], floor: -32)
        expectRanges(detector.detect(in: audio), quiet)
    }

    @Test func aClickDoesNotBreakASilence() {
        var (audio, _) = SyntheticSpeech.make([(false, 1.0), (true, 1.0), (false, 1.0)])
        // A 10 ms click in the middle of the silence.
        let clickStart = audio.index(at: 1.5)
        for index in clickStart..<(clickStart + 160) { audio.samples[index] = index.isMultiple(of: 2) ? 0.5 : -0.5 }
        expectRanges(detector.detect(in: audio), [TimeRange(start: 1.0, end: 2.0)])
    }

    @Test func emptyAudioHasNoSilences() {
        #expect(detector.detect(in: AudioSamples(samples: [], sampleRate: 16_000)).isEmpty)
    }

    @Test func shortRunsAreFilledOnlyBetweenOtherRuns() {
        var flags = [false, true, false, false, true, true, true, false]
        EnergySilenceDetector.fillShortRuns(of: false, in: &flags, shorterThan: 2)
        // The leading single `false` touches the start, so it stays; the inner one flips.
        #expect(flags == [false, true, false, false, true, true, true, false])
        var inner = [true, false, true, true]
        EnergySilenceDetector.fillShortRuns(of: false, in: &inner, shorterThan: 2)
        #expect(inner == [true, true, true, true])
    }
}

@Suite struct SpeechGapTests {
    @Test func silencesAreTheGapsBetweenSpeech() {
        let gaps = SpeechGaps.silences(
            between: [TimeRange(start: 0.5, end: 1.0), TimeRange(start: 1.1, end: 2.0), TimeRange(start: 2.5, end: 3.0)],
            duration: 4,
            minimum: 0.2
        )
        #expect(gaps == [TimeRange(start: 0, end: 0.5), TimeRange(start: 2.0, end: 2.5), TimeRange(start: 3.0, end: 4)])
    }

    @Test func overlappingSpeechIsMerged() {
        let gaps = SpeechGaps.silences(
            between: [TimeRange(start: 0, end: 2.0), TimeRange(start: 1.0, end: 1.5)],
            duration: 3,
            minimum: 0.2
        )
        #expect(gaps == [TimeRange(start: 2.0, end: 3)])
    }
}

@Suite struct AudioChunkerTests {
    @Test func shortAudioIsOnePiece() {
        #expect(AudioChunker.chunks(duration: 10, silences: [], maximumDuration: 30) == [TimeRange(start: 0, end: 10)])
    }

    @Test func cutsInTheMiddleOfTheLongestSilence() {
        let silences = [TimeRange(start: 18, end: 19), TimeRange(start: 22, end: 25), TimeRange(start: 40, end: 41)]
        let chunks = AudioChunker.chunks(duration: 50, silences: silences, maximumDuration: 30)
        #expect(chunks == [TimeRange(start: 0, end: 23.5), TimeRange(start: 23.5, end: 50)])
    }

    @Test func silenceBeforeTheWindowIsNotUsed() {
        // A silence at 5 s would make a tiny first piece, so it's ignored.
        let chunks = AudioChunker.chunks(duration: 40, silences: [TimeRange(start: 5, end: 8)], maximumDuration: 30)
        #expect(chunks == [TimeRange(start: 0, end: 30), TimeRange(start: 30, end: 40)])
    }

    @Test func piecesCoverEverythingAndStayShortEnough() {
        let silences = stride(from: 3.0, to: 600, by: 7.3).map { TimeRange(start: $0, end: $0 + 0.4) }
        let chunks = AudioChunker.chunks(duration: 600, silences: silences, maximumDuration: 25)
        #expect(chunks.first?.start == 0)
        #expect(chunks.last?.end == 600)
        for (earlier, later) in zip(chunks, chunks.dropFirst()) {
            #expect(earlier.end == later.start)
        }
        #expect(chunks.allSatisfy { $0.duration <= 25 + 1e-9 })
        // Every cut but the last piece's end falls inside a silence.
        for chunk in chunks.dropLast() {
            #expect(silences.contains { $0.start <= chunk.end && chunk.end <= $0.end })
        }
    }
}

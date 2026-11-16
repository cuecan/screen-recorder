import AVFoundation
import AudioKit
import Testing
@testable import TranscribeKit

@Suite struct AppleSpeechAnalysisTests {
    @Test func piecesCoverTheWholeBufferInOrder() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 40_000))
        buffer.frameLength = 40_000
        let samples = try #require(buffer.int16ChannelData?[0])
        for index in 0..<40_000 { samples[index] = Int16(truncatingIfNeeded: index) }

        let pieces = try AppleSpeechAnalysis.pieces(of: buffer, frames: 16_000)
        #expect(pieces.map(\.frameLength) == [16_000, 16_000, 8_000])
        var joined: [Int16] = []
        for piece in pieces {
            let data = try #require(piece.int16ChannelData?[0])
            joined += UnsafeBufferPointer(start: data, count: Int(piece.frameLength))
        }
        #expect(joined == (0..<40_000).map { Int16(truncatingIfNeeded: $0) })
    }

    @Test func convertingKeepsTheDuration() throws {
        let audio = AudioSamples(samples: [Float](repeating: 0.1, count: 48_000 * 3), sampleRate: 48_000)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let converted = try audio.pcmBuffer(in: format)
        #expect(abs(Int(converted.frameLength) - 48_000) <= 16, "Three seconds at 16 kHz, give or take a resampler's edge.")
    }
}

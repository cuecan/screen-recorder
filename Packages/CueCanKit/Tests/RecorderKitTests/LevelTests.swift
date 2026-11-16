import AVFoundation
import Foundation
import Testing
@testable import RecorderKit

@Suite struct LevelTests {
    @Test func windowsAreTwentyMillisecondsWithTheirPeakAndRMS() {
        var analyzer = LevelAnalyzer(sampleRate: 48_000)
        #expect(analyzer.samplesPerWindow == 960)
        let first = analyzer.append([Float](repeating: 0.5, count: 900))
        #expect(first.isEmpty, "Not a full window yet.")
        let next = analyzer.append([Float](repeating: -0.5, count: 60) + [Float](repeating: 0, count: 960))
        #expect(next.count == 2)
        #expect(next[0].peak == 0.5)
        #expect(abs(next[0].rms - 0.5) < 1e-6)
        #expect(next[1] == .silence)
        #expect(abs(next[0].peakDecibels - -6.02) < 0.01)
    }

    @Test func theMeterTurnsAmberThenRedNearFullScale() {
        #expect(LevelZone(peakDecibels: -20) == .normal)
        #expect(LevelZone(peakDecibels: -12) == .hot)
        #expect(LevelZone(peakDecibels: -2) == .clipping)
    }
}

@Suite struct WAVStreamWriterTests {
    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "cuecan-wav-\(UUID().uuidString).wav")
    }

    @Test func theLargestPayloadHasCompleteSamplesAndRepresentableHeaderSizes() {
        let limit = WAVStreamWriter.maximumDataBytes
        let header = WAVStreamWriter.header(dataBytes: limit, sampleRate: 48_000)
        let riffSize = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        let dataSize = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self)) }
        #expect(limit.isMultiple(of: 4))
        #expect(limit + UInt64(header.count) <= UInt64(UInt32.max))
        #expect(UInt64(riffSize) + 8 == UInt64(header.count) + limit)
        #expect(UInt64(dataSize) == limit)
    }

    @Test func aBufferBeyondTheSizeLimitIsRejectedAndTheRecordingStillFinishes() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try WAVStreamWriter(url: url, sampleRate: 48_000, dataByteLimit: 8)
        try writer.append([0.1, 0.2])
        #expect(throws: RecorderError.self) { try writer.append([0.3]) }
        #expect(writer.duration == 2.0 / 48_000)
        try writer.finish()
        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 2)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2))
        try file.read(into: buffer)
        #expect(buffer.floatChannelData?[0][0] == 0.1)
        #expect(buffer.floatChannelData?[0][1] == 0.2)
        #expect(try Data(contentsOf: url).count == 52, "The rejected buffer must never reach disk.")
    }

    @Test func aFinishedFileReadsBackExactly() throws {
        let url = temporaryURL()
        let writer = try WAVStreamWriter(url: url, sampleRate: 48_000)
        let samples = (0..<48_000).map { Float(sin(Double($0) / 10)) * 0.25 }
        try writer.append(Array(samples[..<20_000]))
        try writer.append(Array(samples[20_000...]))
        try writer.finish()
        #expect(abs(writer.duration - 1) < 1e-9)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.length == 48_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000))
        try file.read(into: buffer)
        #expect(buffer.floatChannelData?[0][12_345] == samples[12_345])
    }

    @Test func aFileLeftOpenStillReadsUpToTheLastFlush() throws {
        let url = temporaryURL()
        let writer = try WAVStreamWriter(url: url, sampleRate: 48_000)
        // 2.5 s written, never finished: the app stopped suddenly.
        for _ in 0..<5 { try writer.append([Float](repeating: 0.1, count: 24_000)) }
        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 96_000, "Up to the last whole second's header update.")
        _ = writer
    }
}

@Suite struct ClockTests {
    @Test func pausesComeOutOfEveryTrackAlike() {
        var timeline = PauseTimeline()
        timeline.pause(at: 10)
        #expect(timeline.adjusted(11) == nil, "Dropped while paused.")
        timeline.resume(at: 14)
        #expect(timeline.adjusted(9) == 9)
        #expect(timeline.adjusted(15) == 11)
        timeline.pause(at: 20)
        timeline.resume(at: 21)
        #expect(timeline.adjusted(22) == 17)
        #expect(timeline.pausedDuration == 5)
    }

    @Test func theClockStartsAtRecordAndDropsEarlierBuffers() {
        let clock = RecordingClock()
        #expect(clock.place(100) == nil, "Not started.")
        clock.start(at: 100)
        #expect(clock.place(99.9) == nil)
        #expect(clock.place(102.5) == 2.5)
        clock.pause(at: 103)
        clock.resume(at: 105)
        #expect(clock.place(106) == 4)
    }

    @Test func retimingMovesEverySample() throws {
        var format: CMAudioFormatDescription?
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 4096, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 4096, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        var buffer: CMSampleBuffer?
        let data = try #require(block)
        let audioFormat = try #require(format)
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: data, formatDescription: audioFormat, sampleCount: 1024, presentationTimeStamp: CMTime(seconds: 500, preferredTimescale: 48_000), packetDescriptions: nil, sampleBufferOut: &buffer)
        let original = try #require(buffer)
        let retimed = try #require(TrackWriter.retimed(original, to: CMTime(seconds: 1.5, preferredTimescale: 48_000)))
        #expect(CMSampleBufferGetPresentationTimeStamp(retimed).seconds == 1.5)
        #expect(CMSampleBufferGetNumSamples(retimed) == 1024)
    }
}

import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import RecorderKit

/// A frame that doesn't move time on made the movie writer fail for good. The writer drops it
/// instead and the file finishes.
struct TrackWriterTimingTests {
    @Test func anUnchangedScreensLastPictureLastsUntilRecordingStops() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "static-screen-tail-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = TrackWriter(url: url, kind: .video(frameRate: 60))
        // The screen changes at 5 and 6 s on the shared clock, then stays still until Stop at 10 s.
        for time in [5.0, 6.0] {
            writer.append(try frame(at: time, shade: 150), at: time)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await writer.finish(holdingLastFrameUntil: 10))
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 5) < 0.001)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let finalPicture = try await generator.image(at: CMTime(seconds: 4.9, preferredTimescale: 600))
        #expect(finalPicture.image.width == 320)
        #expect(abs(finalPicture.actualTime.seconds - 1) < 0.001, "The final unchanged picture is held, without adding a black tail.")
        // Finalization then cuts every track. The passthrough copy must retain real sample coverage,
        // rather than just a movie-level duration that hides a short video stream.
        let cut = try await TrackTrimmer.trimmedCopy(of: url, keeping: .init(start: 0, end: 5))
        defer { try? FileManager.default.removeItem(at: cut) }
        let cutAsset = AVURLAsset(url: cut)
        let track = try #require(try await cutAsset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: cutAsset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var lastSampleEnd = 0.0
        while let sample = output.copyNextSampleBuffer() {
            lastSampleEnd = max(lastSampleEnd, CMSampleBufferGetPresentationTimeStamp(sample).seconds + CMSampleBufferGetDuration(sample).seconds)
        }
        #expect(reader.status == .completed)
        #expect(abs(lastSampleEnd - 5) < 0.001)
    }

    /// A small grey frame at a time, as a capture would send it.
    private func frame(at time: TimeInterval, shade: Int, duration: CMTime = CMTime(value: 1, timescale: 60)) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
        let buffer = try #require(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), Int32(shade % 255), CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: try #require(format), sampleTiming: &timing, sampleBufferOut: &sample)
        return try #require(sample)
    }

    @Test func framesThatDontMoveTimeOnAreDroppedAndTheFileFinishes() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "timing-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = TrackWriter(url: url, kind: .video(frameRate: 60))
        let failed = Failed()
        writer.onFailure { _ in Task { await failed.set() } }
        // Three seconds at 60 fps, with frames at the same time as the one before and earlier, as bunched
        // screen frames can come; the writer fails a couple of frames after either without the guard.
        var times = (0..<180).map { Double($0) / 60 }
        times.insert(60.0 / 60, at: 61)
        times.insert(99.5 / 60, at: 102)
        for (index, time) in times.enumerated() {
            writer.append(try frame(at: time, shade: index), at: time)
            try await Task.sleep(for: .milliseconds(3))
        }
        #expect(writer.outOfOrder == 2)
        #expect(try await writer.finish())
        #expect(await failed.value == false)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 3) < 0.1, "\(duration)")
    }

    @Test(arguments: [30, 60], [true, false])
    func durationlessCaptureKeepsTheWholeLastFrame(rate: Int, invalid: Bool) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "last-frame-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = TrackWriter(url: url, kind: .video(frameRate: rate))
        for index in 0..<12 {
            let time = Double(index) / Double(rate)
            writer.append(try frame(at: time, shade: 100, duration: invalid ? .invalid : .zero), at: time)
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try await writer.finish())
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let last = try #require(writer.lastWrittenTime)
        let first = try #require(writer.firstTime)
        #expect(abs(duration - (last - first + 1.0 / Double(rate))) < 0.001,
                "The final accepted frame needs its full display interval: \(duration)")
    }

    @Test func aProvidedVideoDurationIsPreserved() throws {
        let interval = CMTime(value: 1, timescale: 24)
        let sample = try frame(at: 5, shade: 100, duration: interval)
        let retimed = try #require(TrackWriter.retimed(sample, to: CMTime(seconds: 12, preferredTimescale: 48_000),
                                                     fallbackDuration: CMTime(value: 1, timescale: 60)))
        #expect(CMTimeCompare(CMSampleBufferGetDuration(retimed), interval) == 0)
        #expect(CMTimeCompare(CMSampleBufferGetDuration(sample), interval) == 0)
        #expect(CMSampleBufferGetPresentationTimeStamp(sample).seconds == 5)
    }

    private actor Failed {
        var value = false
        func set() { value = true }
    }
}

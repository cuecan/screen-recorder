import AVFoundation
import Foundation
import ProjectKit
import Testing
@testable import RecorderKit

/// A take is cut to the time its pictures and its voice all cover (docs/decisions.md, 87).
@Suite struct TakeSpanTests {
    func track(_ kind: SourceTrack.Kind, _ first: TimeInterval, _ duration: TimeInterval) -> TakeSpan.Track {
        TakeSpan.Track(kind: kind, first: first, duration: duration)
    }

    @Test func theTakeIsTheTimeEveryPictureAndTheVoiceCover() throws {
        let screen = track(.screen, 10.007, 10.417), camera = track(.camera, 10.023, 10.413), mic = track(.microphone, 10.001, 10.464)
        let span = try #require(TakeSpan(tracks: [screen, camera, mic], lipSync: 0))
        #expect(span.start == 10.023 && abs(span.end - 20.424) < 1e-9)
        for one in [screen, camera, mic] {
            let cut = try #require(span.cut(for: one))
            #expect(cut.startOffset == 0)
            #expect(abs(cut.keep.duration - span.duration) < 1e-9, "Every track is as long as the take.")
            #expect(abs(one.first + cut.keep.start - span.start) < 1e-9)
        }
    }

    /// The camera's pictures play earlier by the lip sync, so that's where it's cut: later in its own file.
    @Test func theCameraIsCutWhereItsLipSyncPlaysIt() throws {
        let screen = track(.screen, 0.007, 10.417), camera = track(.camera, 0.023, 10.413), mic = track(.microphone, 0.001, 10.464)
        let span = try #require(TakeSpan(tracks: [screen, camera, mic], lipSync: 0.111))
        // Moved 111 ms earlier the camera starts before the screen, so the screen starts the take; the
        // camera, ending at 10.325, ends it.
        #expect(span.lipSync == 0.111)
        #expect(span.start == 0.007 && abs(span.end - 10.325) < 1e-9)
        let cut = try #require(span.cut(for: camera))
        #expect(abs(cut.keep.start - 0.095) < 1e-9 && abs(cut.keep.end - 10.413) < 1e-9)
        // The lip sync is in the cut itself: the file starts at zero like the others, and nothing moves it after.
        #expect(cut.startOffset == 0 && abs(cut.keep.duration - span.duration) < 1e-9)
        #expect(try #require(span.cut(for: mic)).startOffset == 0)
        // A camera ahead of the mic is cut earlier in its file instead.
        let ahead = try #require(TakeSpan(tracks: [screen, camera, mic], lipSync: -0.05))
        let early = try #require(ahead.cut(for: camera))
        #expect(abs(ahead.start - 0.073) < 1e-9)
        #expect(early.startOffset == 0 && early.keep.start == 0)
    }

    @Test func theLipSyncIsLimitedAndRoundedAndOnlyWithACameraAndSound() {
        #expect(TakeSpan.lipSync(0.1114, for: [.screen, .camera, .microphone]) == 0.111)
        #expect(TakeSpan.lipSync(0.9, for: [.camera, .systemAudio]) == TakeSpan.lipSyncLimit)
        #expect(TakeSpan.lipSync(0.1, for: [.screen, .microphone]) == 0)
        #expect(TakeSpan.lipSync(0.1, for: [.screen, .camera]) == 0)
    }

    @Test func systemAudioNeverShortensATakeAndIsCutWhereItRunsPastIt() throws {
        let screen = track(.screen, 0.02, 10), mic = track(.microphone, 0.01, 10.2)
        // It started first and stopped more than a second early, as on one of real takes.
        let early = track(.systemAudio, 0, 8.7)
        let span = try #require(TakeSpan(tracks: [screen, mic, early], lipSync: 0))
        #expect(span.start == 0.02 && span.end == 10.02)
        let cut = try #require(span.cut(for: early))
        #expect(abs(cut.keep.start - 0.02) < 1e-9 && cut.keep.end == 8.7 && cut.startOffset == 0)
        // Starting late, it keeps its place; with nothing inside the take, it isn't part of it.
        let late = try #require(span.cut(for: track(.systemAudio, 1.02, 30)))
        #expect(late.keep.start == 0 && abs(late.keep.end - 9) < 1e-9 && abs(late.startOffset - 1) < 1e-9)
        #expect(span.cut(for: track(.systemAudio, 11, 2)) == nil)
        // Alone, it's the take.
        #expect(TakeSpan(tracks: [early], lipSync: 0)?.duration == 8.7)
    }

    @Test func tracksWithNoTimeInCommonHaveNoSpan() {
        #expect(TakeSpan(tracks: [track(.screen, 0, 2), track(.camera, 3, 2)], lipSync: 0) == nil)
        #expect(TakeSpan(tracks: [], lipSync: 0) == nil)
    }

    // MARK: - Placing a take's tracks

    func media(_ kind: SourceTrack.Kind, _ first: TimeInterval, _ duration: TimeInterval) -> RecordingFinalizer.MediaTrack {
        .init(kind: kind, url: URL(filePath: "/tmp/cuecan-span-\(kind.rawValue)"), first: first, media: MediaInfo(duration: duration))
    }

    @Test func aSavedTakesTracksStartAtZeroAndEndTogether() async throws {
        let tracks = [media(.screen, 5.007, 10.417), media(.camera, 5.023, 10.413), media(.microphone, 5.001, 10.464), media(.systemAudio, 5, 10.42)]
        let cuts = Cuts()
        let placed = try #require(try await RecordingFinalizer.place(tracks, lipSync: 0.111, file: { .inProject($0.url.lastPathComponent) },
            trim: { await cuts.record($0) },
            probe: { _, url in MediaInfo(duration: await cuts.length(of: url)) }))
        #expect(placed.isCut && placed.lipSync == 0.111)
        #expect(abs(placed.origin - 5.007) < 1e-9, "Source time zero is where the take starts, for the screen log.")
        #expect(placed.tracks.map(\.kind) == [.screen, .camera, .microphone, .systemAudio])
        #expect(placed.tracks.map(\.startOffset) == [0, 0, 0, 0])
        for track in placed.tracks { #expect(abs(track.media.duration - 10.318) < 1e-9) }
        // The source is the take.
        let source = Source(id: SourceID(number: 1), name: "Take", origin: .recorded, tracks: placed.tracks)
        #expect(abs(source.duration - 10.318) < 1e-9)
        #expect(await cuts.all.count == 4)
    }

    @Test func theProjectKeepsTheLipSyncATakeWasSavedWithForACameraWithSound() throws {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-span-\(UUID())"), title: "Lip sync")
        defer { try? FileManager.default.removeItem(at: folder.url) }
        func track(_ kind: SourceTrack.Kind) -> SourceTrack { SourceTrack(kind: kind, file: .inProject("recordings/\(kind.rawValue)"), media: MediaInfo(duration: 10)) }
        var recorded = RecordedSource(name: "Take", tracks: [track(.screen), track(.camera), track(.microphone)], captureArea: nil, droppedBuffers: [:], micLostAt: nil)
        recorded.lipSync = 0.111
        #expect(try recorded.add(to: folder, format: nil).lipSync == 0.111)
        #expect(try folder.loadProject().sources.first?.lipSync == 0.111)
        // Without a camera there's nothing it moved.
        recorded.tracks = [track(.screen), track(.microphone)]
        #expect(try recorded.add(to: folder, format: nil).lipSync == nil)
    }

    @Test func aTakeThatCantBeCutIsKeptAsItWasRecorded() async throws {
        let tracks = [media(.screen, 5.007, 10.417), media(.camera, 5.023, 10.413), media(.microphone, 5.001, 10.464)]
        let placed = try #require(try await RecordingFinalizer.place(tracks, lipSync: 0.111, file: { .inProject($0.url.lastPathComponent) },
            trim: { _ in throw RecorderError.unexpectedBuffer },
            probe: { _, _ in MediaInfo(duration: 0) }))
        #expect(!placed.isCut && placed.lipSync == 0.111)
        // The camera is still moved earlier by its lip sync, which here makes it the first to start.
        #expect(abs(placed.origin - 4.912) < 1e-9)
        #expect(placed.tracks.map { ($0.startOffset * 1000).rounded() } == [95, 0, 89])
        #expect(placed.tracks.map(\.media.duration) == [10.417, 10.413, 10.464])
        #expect(try await RecordingFinalizer.place([], lipSync: 0, file: { .inProject($0.url.lastPathComponent) }, trim: { _ in }, probe: { _, _ in MediaInfo(duration: 0) }) == nil)
    }

    @Test func aTakeWhoseFilesCouldNotBeRestoredDoesNotGetOriginalClockMetadata() async throws {
        let tracks = [media(.screen, 5, 10), media(.camera, 5.02, 10), media(.microphone, 5, 10)]
        await #expect(throws: TrackTrimPublication.RestorationFailure.self) {
            try await RecordingFinalizer.place(tracks, lipSync: 0.111, file: { .inProject($0.url.lastPathComponent) },
                trim: { _ in throw TrackTrimPublication.RestorationFailure(files: tracks.map(\.url), reason: "Injected recovery failure") },
                probe: { _, _ in MediaInfo(duration: 10) })
        }
    }

    private actor Cuts {
        var all: [URL: TimeRange] = [:]
        func record(_ cuts: [(url: URL, keep: TimeRange)]) { for cut in cuts { all[cut.url] = cut.keep } }
        func length(of url: URL) -> TimeInterval { all[url]?.duration ?? 0 }
    }

    // MARK: - Cutting real files

    /// Thirty frames a second, each a flat grey of its own number, so a frame can be told from the next.
    private func writeVideo(to url: URL, frames: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(index * 4), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: 30))
        await writer.finishWriting()
    }

    /// The grey of the frame showing at a time.
    private func grey(of url: URL, at time: TimeInterval) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600_000)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Int(pixel[1])
    }

    @Test func aMovieCutPartwayThroughAFrameOpensOnThatFrameAndAWAVIsCutToTheSample() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-trim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "screen.mov"), sound = folder.appending(path: "mic.wav")
        try await writeVideo(to: movie, frames: 60)
        // A ramp, so each sample says where it was.
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        do {
            let file = try AVAudioFile(forWriting: sound, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000))
            buffer.frameLength = 96_000
            let samples = try #require(buffer.floatChannelData?[0])
            for index in 0..<96_000 { samples[index] = Float(index) / 96_000 }
            try file.write(from: buffer)
        }
        // Frame 15 runs from 0.5 to 0.533: the cut starts inside it.
        let keep = TimeRange(start: 0.51, end: 1.51)
        var uncut: [TimeInterval: Int] = [:]
        for time in [0.49, 0.51, 0.54, 1.5] { uncut[time] = try await grey(of: movie, at: time) }
        #expect(Set(uncut.values).count == 4, "Each frame has its own grey.")
        try await TrackTrimmer.trim([(movie, keep), (sound, keep)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted() == ["mic.wav", "screen.mov"],
                "The cut files replace the originals, with nothing left beside them.")

        let video = try await MediaProbe.probe(movie, captureRate: 30)
        #expect(abs(video.duration - 1) < 0.002)
        // Frames are four grey levels apart, so a level of decoding is never mistaken for another frame.
        #expect(abs(try await grey(of: movie, at: 0) - (uncut[0.51] ?? 0)) <= 1, "It opens on the frame that was showing, not the next.")
        #expect(abs(try await grey(of: movie, at: 0.03) - (uncut[0.54] ?? 0)) <= 1)
        #expect(abs(try await grey(of: movie, at: 0.99) - (uncut[1.5] ?? 0)) <= 1)

        let cut = try AVAudioFile(forReading: sound)
        #expect(cut.fileFormat.sampleRate == 48_000 && cut.fileFormat.channelCount == 1)
        #expect(abs(Int(cut.length) - 48_000) <= 1)
        let read = try #require(AVAudioPCMBuffer(pcmFormat: cut.processingFormat, frameCapacity: 16))
        try cut.read(into: read, frameCount: 16)
        let first = try #require(read.floatChannelData?[0][0])
        #expect(abs(Double(first) * 96_000 - 0.51 * 48_000) <= 1, "The first sample is the one at the cut.")
    }

    @Test func aFileThatCantBeCutLeavesEveryOriginalAsItWas() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-trim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "screen.mov"), broken = folder.appending(path: "camera.mov")
        try await writeVideo(to: movie, frames: 30)
        try Data("not a movie".utf8).write(to: broken)
        let before = try Data(contentsOf: movie)
        await #expect(throws: (any Error).self) {
            try await TrackTrimmer.trim([(movie, TimeRange(start: 0.2, end: 0.8)), (broken, TimeRange(start: 0.2, end: 0.8))])
        }
        #expect(try Data(contentsOf: movie) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted() == ["camera.mov", "screen.mov"])
    }
}

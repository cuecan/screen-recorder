import AVFoundation
import CoreImage
import Foundation
import Testing
import ProjectKit
@testable import RenderKit

/// How much captions cost, with them on and off, on synthetic footage at a recording's sizes: a 2560 × 2160
/// screen and a 1920 × 1080 camera on a 60 fps frame clock, with continuous speech so a page is always up.
/// Prints what it measures; runs only with `CUECAN_BENCH` set (`CUECAN_BENCH=1 swift test --filter
/// CaptionPerformanceTests`). Not a check of taste or of the running app.
@Suite(.serialized) struct CaptionPerformanceTests {
    static let seconds = 4.0

    @Test func compositorAndPlaybackWithCaptionsOnAndOff() async throws {
        guard ProcessInfo.processInfo.environment["CUECAN_BENCH"] != nil else { return }
        let folder = try await Self.makeTake()
        print("Load average at start: \(Self.loadAverage())")
        for (name, outputs, scale) in [("1080p video", [OutputShape.landscape], 1.0), ("editor, video and Short side by side at 1080", [.landscape, .vertical], 1.0),
                                       ("4K video", [.landscape], 2.0)] {
            var results: [Bool: [Double]] = [:]
            // Off, on, off, on: so the machine's load falls on both alike.
            for captions in [false, true, false, true] {
                try folder.updateEdit(author: .system("Bench"), reason: "Captions") { edit in
                    edit.setCaptions(captions)
                }
                let built = try await CompositionBuilder.build(try RenderInputs.load(folder), outputs: outputs, scale: scale)
                results[captions, default: []] += try await Self.frameTimes(built)
            }
            print("\(name), compositor per frame through AVAssetReader: off \(Self.summary(results[false] ?? [])); on \(Self.summary(results[true] ?? []))")
        }

        for outputs in [[OutputShape.landscape], [.landscape, .vertical]] {
            var lines: [String] = []
            for captions in [false, true, false, true] {
                try folder.updateEdit(author: .system("Bench"), reason: "Captions") { edit in
                    edit.setCaptions(captions)
                }
                let built = try await CompositionBuilder.build(try RenderInputs.load(folder), outputs: outputs, scale: 1)
                let (delivered, expected, stalls) = try await Self.playback(built)
                lines.append("\(captions ? "on" : "off") \(delivered)/\(expected) frames, \(stalls) gaps over 2 frames")
            }
            print("AVPlayer real-time playback at 60 fps, \(outputs.map(\.title).joined(separator: " + ")), \(Self.seconds) s: \(lines.joined(separator: "; "))")
        }
        print("Load average at end: \(Self.loadAverage())")
    }

    /// Wall time to make each frame, reading the composition as fast as it goes.
    static func frameTimes(_ built: BuiltComposition) async throws -> [Double] {
        let reader = try AVAssetReader(asset: built.composition)
        let tracks = try await built.composition.loadTracks(withMediaType: .video)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = built.videoComposition
        reader.add(output)
        reader.startReading()
        var times: [Double] = []
        var last = DispatchTime.now().uptimeNanoseconds
        while output.copyNextSampleBuffer() != nil {
            let now = DispatchTime.now().uptimeNanoseconds
            times.append(Double(now - last) / 1_000_000)
            last = now
        }
        // The first frame carries the reader's start-up.
        return Array(times.dropFirst())
    }

    /// Plays the composition in real time and asks for a new frame 60 times a second, as a display would.
    @MainActor static func playback(_ built: BuiltComposition) async throws -> (delivered: Int, expected: Int, stalls: Int) {
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        while item.status == .unknown { try await Task.sleep(for: .milliseconds(10)) }
        await player.preroll(atRate: 1)
        player.play()
        var delivered = 0
        var stalls = 0
        var lastFrame: Double?
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            let now = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: now), output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil) != nil {
                delivered += 1
                if let lastFrame, now.seconds - lastFrame > 2.5 / 60 { stalls += 1 }
                lastFrame = now.seconds
            }
            try await Task.sleep(for: .microseconds(16_667))
        }
        player.pause()
        return (delivered, Int(seconds * 60), stalls)
    }

    static func summary(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "none" }
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        func at(_ q: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))] }
        return String(format: "mean %.2f ms, median %.2f, p95 %.2f, max %.2f (n=%d)", mean, at(0.5), at(0.95), sorted.last ?? 0, values.count)
    }

    static func loadAverage() -> String {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return loads.map { String(format: "%.1f", $0) }.joined(separator: " ")
    }

    /// A take with continuous speech: four-letter words every 0.25 s, a pause every 8 words.
    static func makeTake() async throws -> ProjectFolder {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-caption-bench-\(UUID().uuidString)")
        let folder = try ProjectFolder.create(at: url, title: "Caption bench")
        let recordings = folder.url(for: .recordings)
        try await writeFlatVideo(width: 2560, height: 2160, to: recordings.appending(path: "screen.mov"))
        try await writeFlatVideo(width: 1920, height: 1080, to: recordings.appending(path: "camera.mov"))
        try SyntheticMedia.writeTone(seconds: seconds, to: recordings.appending(path: "mic.wav"))
        try folder.updateProject { project in
            project.addSource(
                name: "Screen recording", origin: .recorded,
                tracks: [
                    SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: seconds, video: .init(width: 2560, height: 2160, frameRate: 60, captureRate: 60, codec: "avc1"))),
                    SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), media: MediaInfo(duration: seconds, video: .init(width: 1920, height: 1080, frameRate: 60, captureRate: 60, codec: "avc1"))),
                    SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), media: MediaInfo(duration: seconds, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
                ],
                captureArea: CaptureArea(ratio: .thirtyTwoByTwentySeven, heightPoints: 1080),
                layout: .sideBySide(.thirtyTwoByTwentySeven)
            )
        }
        var pieces: [Piece] = []
        let vocabulary = ["here", "what", "this", "does", "when", "your", "code", "runs", "fast", "now."]
        var time = 0.0
        var index = 0
        while time + 0.25 < seconds {
            pieces.append(.word(vocabulary[index % vocabulary.count], time, time + 0.22))
            index += 1
            time += index % 8 == 0 ? 0.5 : 0.25
        }
        _ = try folder.addTranscript(makeTranscript(duration: seconds, pieces).draft, for: SourceID(number: 1))
        try folder.updateEdit(author: .system("Bench"), reason: "Whole take") { edit in
            edit.main = [clip(1, 0, seconds)]
        }
        return folder
    }

    /// A video of one flat colour, made quickly: 60 frames a second.
    static func writeFlatVideo(width: Int, height: Int, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var pattern: UInt32 = 0xFF50_3020
        for frame in 0..<Int(seconds * 60) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset_pattern4(base, &pattern, CVPixelBufferGetBytesPerRow(buffer) * height)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 60))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

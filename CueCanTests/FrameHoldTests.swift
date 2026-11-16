import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import CueCan

/// A playing item's frame must survive a rapid replacement before the next item has decoded anything.
@MainActor
struct FrameHoldTests {
    @Test func aPlayingFrameIsCapturedAndAnUndecodedReplacementKeepsIt() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-frame-hold-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await writeRedVideo(to: url)
        let item = AVPlayerItem(url: url)
        FrameHold.attach(to: item)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        let hold = FrameHold()
        player.play()
        let deadline = ContinuousClock.now + .seconds(5)
        while hold.image == nil, ContinuousClock.now < deadline, item.status != .failed {
            hold.capture(from: item)
            if hold.image == nil { try await Task.sleep(for: .milliseconds(20)) }
        }
        let image = try #require(hold.image, "The video output must supply a held picture during playback: \(String(describing: item.error))")
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        #expect(pixel[0] > 200 && pixel[1] < 40 && pixel[2] < 40, "A held image must contain the decoded red picture, not a black buffer.")
        let cold = AVPlayerItem(url: url)
        FrameHold.attach(to: cold)
        hold.capture(from: cold)
        #expect(hold.image === image, "A rapid second replacement with no decoded frame must retain the last useful picture.")
        hold.capture(from: nil)
        #expect(hold.image === image)
    }

    private func writeRedVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var allocated: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &allocated)
        let buffer = try #require(allocated)
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for row in 0..<64 {
            for column in 0..<64 {
                let offset = row * CVPixelBufferGetBytesPerRow(buffer) + column * 4
                bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 255; bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<48 {
            while !input.isReadyForMoreMediaData {
                try #require(writer.status == .writing, "\(String(describing: writer.error))")
                try await Task.sleep(for: .milliseconds(2))
            }
            try #require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
        await writer.finishWriting()
        #expect(writer.status == .completed, "\(String(describing: writer.error))")
    }
}

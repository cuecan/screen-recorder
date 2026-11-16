import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import ProjectKit
import UniformTypeIdentifiers

/// Takes stills of the edit through the same compositor the export uses, so a still shows exactly what
/// the export will: the layout, the look, the bubble and the overlays.
///
/// It reads frames with `AVAssetReaderVideoCompositionOutput`, the export's own path, rather than
/// `AVAssetImageGenerator`: on macOS 27.2 the generator gives a custom compositor no frames at all from
/// 10-bit HEVC, such as another screen recorder's and iPhone footage, and every still comes out black.
public enum FrameGrabber {
    /// Still requests are frequent during framing and project changes. Reuse the thread-safe context
    /// so its Metal command queues and compiled kernels do not accumulate with each cancelled request.
    private static let context = CIContext(options: [.cacheIntermediates: false])
    // Admission policy, including abandoned work: normal previews need few readers, while a stuck
    // decoder must not permit unbounded replacement readers. Slots are released only by their workers.
    // VERIFY: 16 is headroom chosen without a measurement. Requests past it wait their turn, and are
    // refused only once every slot holds abandoned work.
    private static let readers = FrameReadLimit(capacity: 16)

    /// Stills at timeline times, each no wider than `maximumWidth`. With several outputs in the composition,
    /// `output` picks one; nil takes the whole frame.
    public static func stills(of built: BuiltComposition, at times: [TimeInterval], maximumWidth: Int = 960, output: OutputShape? = nil) async throws -> [Still] {
        let crop = output.flatMap { built.rect(of: $0) }.map { rect in
            CGRect(x: rect.minX, y: built.videoComposition.renderSize.height - rect.maxY, width: rect.width, height: rect.height)
        }
        let size = crop?.size ?? built.videoComposition.renderSize
        let scale = min(1, Double(maximumWidth) / max(size.width, 1))
        let frameDuration = built.videoComposition.frameDuration
        let end = built.timeline.duration

        var stills: [Still] = []
        for time in times {
            try Task.checkCancellation()
            // The last frame starts a little before the end.
            let last = Timecode(frameDuration: frameDuration.seconds).frameTime(before: end)
            let clamped = min(max(0, time), last)
            var image = try await frame(of: built, at: clamped, frameDuration: frameDuration)
            if let crop {
                image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            }
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
                throw RenderError.couldNotEncodeImage
            }
            stills.append(Still(time: clamped, jpeg: try jpeg(cgImage), width: cgImage.width, height: cgImage.height))
        }
        return stills
    }

    /// The composited frame showing at a time.
    private static func frame(of built: BuiltComposition, at time: TimeInterval, frameDuration: CMTime) async throws -> CIImage {
        try await FrameReadTask.run(limit: readers) { hasStopped in
            try await readFrame(of: built, at: time, frameDuration: frameDuration, hasStopped: hasStopped)
        }
    }

    /// The caller's wait is bounded separately. Native work owns its visual context until it returns.
    /// VERIFY whether the async provider itself honors task cancellation; do not rely on it for a bound.
    private static func readFrame(of built: BuiltComposition, at time: TimeInterval, frameDuration: CMTime,
                                  hasStopped: @Sendable () -> Bool) async throws -> CIImage {
        guard !hasStopped() else { throw CancellationError() }
        let tracks = built.composition.tracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            throw RenderError.exportFailed("This edit has no recorded picture to preview.")
        }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: built.composition)
        } catch {
            throw RenderError.exportFailed("Couldn't read the edit's picture: \(error.localizedDescription)")
        }
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = built.videoComposition
        let start = CompositionBuilder.cmTime(time)
        // A final-frame read must not ask the compositor for time beyond its last instruction.
        let end = CMTimeMinimum(CMTimeAdd(start, CMTimeMultiply(frameDuration, multiplier: 2)),
                                CMTimeMinimum(built.composition.duration, CompositionBuilder.cmTime(built.timeline.duration)))
        reader.timeRange = CMTimeRange(start: start, end: end)
        let provider = reader.outputProvider(for: output)
        let cancellation = FrameReadCancellation(reader: reader)
        defer { cancellation.cancel() }
        guard !hasStopped() else { throw CancellationError() }
        try cancellation.start()
        guard !hasStopped() else { throw CancellationError() }
        let buffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>?
        do {
            try cancellation.beginRead()
            defer { cancellation.finishRead() }
            buffer = try await provider.next()
        }
        guard !hasStopped() else { throw CancellationError() }
        guard let image = buffer?.withUnsafeSampleBuffer({ sample in
            sample.imageBuffer.map { CIImage(cvPixelBuffer: $0) }
        }) else {
            throw RenderError.exportFailed("Couldn't read a preview frame at \(String(format: "%.2f", time)) s. Try again.")
        }
        return image
    }

    /// Times just either side of every cut, so Claude can see both frames that meet there.
    public static func cutTimes(of built: BuiltComposition, offset: TimeInterval = 0.05) -> [TimeInterval] {
        built.timeline.clips.dropFirst().flatMap { placed in
            [max(0, placed.timeline.start - offset), placed.timeline.start + offset]
        }
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.8) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RenderError.couldNotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.couldNotEncodeImage }
        return data as Data
    }
}

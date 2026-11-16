import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ProjectKit

/// Plumbing-only media: solid-color video and a steady tone, to check that pictures land where the layouts
/// put them. Never for judging how anything looks or sounds.
enum SyntheticMedia {
    struct Color { var red: UInt8; var green: UInt8; var blue: UInt8 }
    static let red = Color(red: 255, green: 0, blue: 0)
    static let blue = Color(red: 0, green: 0, blue: 255)
    static let green = Color(red: 0, green: 255, blue: 0)

    static func writeVideo(_ color: Color, width: Int, height: Int, seconds: Double, to url: URL) async throws {
        try await writeVideo(width: width, height: height, seconds: seconds, to: url) { _, _ in color }
    }

    /// Four known regions make static crops observable instead of testing them on a solid image.
    static func writeQuadrants(width: Int, height: Int, seconds: Double, to url: URL) async throws {
        try await writeVideo(width: width, height: height, seconds: seconds, to: url) { x, y in
            if y < height / 2 { return x < width / 2 ? red : blue }
            return x < width / 2 ? green : Color(red: 255, green: 255, blue: 255)
        }
    }

    private static func writeVideo(width: Int, height: Int, seconds: Double, to url: URL, colorAt: (Int, Int) -> Color) async throws {
        // These fixtures are static pictures. Build the known pixels once, then copy them into each
        // buffer; evaluating a closure per pixel per frame makes the full render suite needlessly slow.
        let visibleRowBytes = width * 4
        var picture = Data(count: visibleRowBytes * height)
        picture.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * visibleRowBytes + x * 4
                    let color = colorAt(x, y)
                    bytes[offset] = color.blue; bytes[offset + 1] = color.green
                    bytes[offset + 2] = color.red; bytes[offset + 3] = 255
                }
            }
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * 30)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
                picture.withUnsafeBytes { pixels in
                    if let source = pixels.baseAddress {
                        for y in 0..<height {
                            base.advanced(by: y * rowBytes).copyMemory(from: source.advanced(by: y * visibleRowBytes), byteCount: visibleRowBytes)
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    static func writeTone(seconds: Double, frequency: Double = 220, amplitude: Float = 0.1, to url: URL) throws {
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let count = Int(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for index in 0..<count {
            buffer.floatChannelData![0][index] = amplitude * Float(sin(2 * .pi * frequency * Double(index) / rate))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    /// A solid-colour PNG, for a still overlay.
    static func writePNG(_ color: Color, width: Int, height: Int, to url: URL) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
    }

    /// The color at a point of a JPEG, from the top left.
    static func pixel(_ jpeg: Data, x: Int, y: Int) -> Color? {
        Pixels(jpeg)?[x, y]
    }

    /// Decode a still once when checking many pixels. Decoding again for each sampled pixel makes a
    /// caption-region assertion perform tens of thousands of full-frame decodes.
    struct Pixels {
        private let context: CGContext

        init?(_ jpeg: Data) {
            guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            self.context = context
        }

        subscript(x: Int, y: Int) -> Color? {
            guard (0..<context.width).contains(x), (0..<context.height).contains(y),
                  let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            let offset = y * context.bytesPerRow + x * 4
            return Color(red: data[offset], green: data[offset + 1], blue: data[offset + 2])
        }
    }
}

extension SyntheticMedia.Color {
    func isClose(to other: SyntheticMedia.Color, within tolerance: Int = 40) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
    }
}

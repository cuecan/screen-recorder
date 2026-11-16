import CoreVideo
import Foundation

/// A camera frame's brightness as a small grid, for finding a flash (``FlashDetector``).
enum FrameBrightness {
    static let columns = 12
    static let rows = 8
    /// Every fourth pixel each way is read: plenty for a mean, and cheap at 30 frames a second.
    private static let stride = 4

    /// Each cell's mean brightness from 0 to 1, row by row from the top left. Nil for a pixel format this
    /// doesn't read.
    static func cells(of pixels: CVPixelBuffer) -> [Float]? {
        // Where the brightness sits in each pixel: how many bytes a pixel takes, and which of them it is.
        let layout: (plane: Int?, bytesPerPixel: Int, offset: Int)
        switch CVPixelBufferGetPixelFormatType(pixels) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8Planar, kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            layout = (0, 1, 0)
        case kCVPixelFormatType_422YpCbCr8: layout = (nil, 2, 1)
        case kCVPixelFormatType_422YpCbCr8_yuvs, kCVPixelFormatType_422YpCbCr8FullRange: layout = (nil, 2, 0)
        // Green stands in for brightness.
        case kCVPixelFormatType_32BGRA: layout = (nil, 4, 1)
        case kCVPixelFormatType_32ARGB: layout = (nil, 4, 2)
        default: return nil
        }
        guard CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base: UnsafeMutableRawPointer?
        let width: Int, height: Int, bytesPerRow: Int
        if let plane = layout.plane {
            base = CVPixelBufferGetBaseAddressOfPlane(pixels, plane)
            width = CVPixelBufferGetWidthOfPlane(pixels, plane)
            height = CVPixelBufferGetHeightOfPlane(pixels, plane)
            bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixels, plane)
        } else {
            base = CVPixelBufferGetBaseAddress(pixels)
            width = CVPixelBufferGetWidth(pixels)
            height = CVPixelBufferGetHeight(pixels)
            bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        }
        guard let base, width >= columns * stride, height >= rows * stride else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        var cells = [Float](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            let top = row * height / rows, bottom = (row + 1) * height / rows
            for column in 0..<columns {
                let left = column * width / columns, right = (column + 1) * width / columns
                var sum = 0, count = 0
                for y in Swift.stride(from: top, to: bottom, by: stride) {
                    let line = bytes + y * bytesPerRow
                    for x in Swift.stride(from: left, to: right, by: stride) {
                        sum += Int(line[x * layout.bytesPerPixel + layout.offset])
                        count += 1
                    }
                }
                cells[row * columns + column] = count > 0 ? Float(sum) / Float(count) / 255 : 0
            }
        }
        return cells
    }
}

import AVFoundation
import CoreImage

/// The frame on screen just before the preview's item is swapped, taken from a video output on the item, so
/// the panels can hold it until the new item has a picture. The player layer only hands out its frame while
/// paused; without this, a swap during playback showed black or an older poster: the flicker seen when
/// Cleanup or Voice changed.
@MainActor final class FrameHold {
    private(set) var image: CGImage?
    private static let context = CIContext()

    /// Gives a new item the output frames are taken from.
    static func attach(to item: AVPlayerItem) {
        item.add(AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]))
    }

    /// Takes the frame the item shows now, if it has one. A rapid second replacement may not have
    /// decoded anything yet, so retain the last useful picture instead of clearing it to black.
    func capture(from item: AVPlayerItem?) {
        guard let item, let output = item.outputs.lazy.compactMap({ $0 as? AVPlayerItemVideoOutput }).first,
              let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil) else { return }
        let frame = CIImage(cvPixelBuffer: buffer)
        if let captured = Self.context.createCGImage(frame, from: frame.extent) { image = captured }
    }
}

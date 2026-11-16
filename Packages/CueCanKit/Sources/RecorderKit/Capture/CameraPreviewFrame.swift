import CoreMedia
import CoreVideo
import Foundation

/// A read-only camera image shared with previews. Display samples are separate from the recording's
/// sample, so display timing and attachments cannot alter what the writer receives.
public struct CameraPreviewFrame: @unchecked Sendable {
    public let pixels: CVPixelBuffer
    public let format: CMVideoFormatDescription
    public let hostTime: TimeInterval

    public init(pixels: CVPixelBuffer, format: CMVideoFormatDescription, hostTime: TimeInterval) {
        self.pixels = pixels
        self.format = format
        self.hostTime = hostTime
    }

    /// References the same pixels without copying them. Immediate display ignores the capture clock.
    public func makeDisplaySample() -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: .invalid,
            presentationTimeStamp: CMTime(seconds: hostTime, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
            let sample,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary],
            let first = attachments.first else { return nil }
        first[kCMSampleAttachmentKey_DisplayImmediately] = true
        return sample
    }
}

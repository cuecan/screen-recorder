import CoreMedia
import CoreVideo
import Foundation
import Testing
@testable import RecorderKit

struct CameraPreviewDeliveryTests {
    @Test func aBusyPreviewHasOneDeliveryAndKeepsOnlyTheNewestFrame() throws {
        let delivery = CameraPreviewDelivery()
        let pixels = try image()
        #expect(delivery.submit(try frame(pixels, at: 1)))
        for number in 2...1_000 { #expect(!delivery.submit(try frame(pixels, at: Double(number)))) }
        #expect(delivery.take()?.frame?.hostTime == 1_000)
        #expect(delivery.take() == nil)
        #expect(delivery.submit(try frame(pixels, at: 1_001)))
        #expect(delivery.take()?.frame?.hostTime == 1_001)
    }

    @Test func clearingAndOldFramesCannotReplaceANewerPicture() throws {
        let delivery = CameraPreviewDelivery()
        let pixels = try image()
        #expect(delivery.submit(try frame(pixels, at: 10)))
        #expect(!delivery.submit(nil))
        let cleared = try #require(delivery.take())
        #expect(cleared.frame == nil)
        #expect(!delivery.submit(try frame(pixels, at: 9)))
        #expect(delivery.take() == nil)
        #expect(delivery.submit(try frame(pixels, at: 11)))
        #expect(delivery.take()?.frame?.hostTime == 11)
    }

    @Test func aBlockedUIReleasesSupersededCameraBuffers() throws {
        var pool: CVPixelBufferPool?
        let attributes = [kCVPixelBufferWidthKey: 64, kCVPixelBufferHeightKey: 64,
                          kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary
        try #require(CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool) == kCVReturnSuccess)
        let buffers = try #require(pool)
        let limit = [kCVPixelBufferPoolAllocationThresholdKey: 4] as CFDictionary
        let delivery = CameraPreviewDelivery()
        // No UI deliveries during this burst. Retaining superseded frames would exhaust the pool.
        for number in 1...1_000 {
            try autoreleasepool {
                var pixels: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, buffers, limit, &pixels)
                try #require(status == kCVReturnSuccess)
                _ = delivery.submit(try frame(try #require(pixels), at: Double(number)))
            }
        }
        #expect(delivery.take()?.frame?.hostTime == 1_000)
    }

    @Test func aDisplaySampleSharesPixelsAndKeepsDisplayAttachmentsOutOfTheRecordingSample() throws {
        let pixels = try image()
        let frame = try frame(pixels, at: 12.5)
        let display = try #require(frame.makeDisplaySample())
        #expect(CFEqual(CMSampleBufferGetImageBuffer(display), pixels))
        #expect(CMSampleBufferDataIsReady(display))
        #expect(CMSampleBufferGetPresentationTimeStamp(display).seconds == 12.5)
        let attachments = try #require(CMSampleBufferGetSampleAttachmentsArray(display, createIfNecessary: false) as? [NSDictionary])
        #expect((attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] as? NSNumber)?.boolValue == true)
        // A second sample has its own attachment dictionary, even though the image is shared.
        let other = try #require(frame.makeDisplaySample())
        let second = try #require(CMSampleBufferGetSampleAttachmentsArray(other, createIfNecessary: false) as? [NSMutableDictionary])
        second.first?[kCMSampleAttachmentKey_DisplayImmediately] = false
        #expect((attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] as? NSNumber)?.boolValue == true)
    }

    private func image() throws -> CVPixelBuffer {
        var pixels: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &pixels) == kCVReturnSuccess)
        return try #require(pixels)
    }

    private func frame(_ pixels: CVPixelBuffer, at time: TimeInterval) throws -> CameraPreviewFrame {
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels,
                                                          formatDescriptionOut: &format) == noErr)
        return CameraPreviewFrame(pixels: pixels, format: try #require(format), hostTime: time)
    }
}

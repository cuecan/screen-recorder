import AVFoundation
import Foundation
import ProjectKit

/// Reads what a file the recorder wrote holds, for its ``SourceTrack``.
public enum MediaProbe {
    /// `captureRate` is the frames a second a video file's capture was set to; every video file needs one.
    public static func probe(_ url: URL, captureRate: Int?) async throws -> MediaInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        var info = MediaInfo(duration: duration.isFinite ? duration : 0)
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            guard let captureRate else { throw RecorderError.couldNotWrite(url, "its capture rate wasn't recorded") }
            let (size, rate, formats) = try await track.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
            let codec = formats.first.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown"
            info.video = MediaInfo.Video(width: Int(size.width), height: Int(size.height), frameRate: Double(rate), captureRate: captureRate, codec: codec)
        }
        if let track = try await asset.loadTracks(withMediaType: .audio).first {
            let formats = try await track.load(.formatDescriptions)
            if let format = formats.first, let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                info.audio = MediaInfo.Audio(sampleRate: stream.mSampleRate, channels: Int(stream.mChannelsPerFrame), codec: fourCC(stream.mFormatID))
            }
        }
        return info
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.allSatisfy { $0.isASCII && !$0.isWhitespace } && !text.isEmpty ? text : String(code)
    }
}

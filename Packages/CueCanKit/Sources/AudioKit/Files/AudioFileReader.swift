import AVFoundation
import Foundation
import ProjectKit

/// Reads the sound from any file AVFoundation opens: WAV, M4A, MOV and MP4, including a video's audio.
public enum AudioFileReader {
    /// One audio track of a file.
    public struct TrackInfo: Sendable, Equatable {
        /// Position among the file's audio tracks, from 0.
        public var index: Int
        public var channels: Int
        public var sampleRate: Double
        public var duration: TimeInterval
    }

    /// The audio tracks in a file. A screen recorder's or QuickTime's recording can hold the mic and system
    /// audio as separate tracks.
    public static func audioTracks(in url: URL) async throws -> [TrackInfo] {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw AudioKitError.unreadable(url, error.localizedDescription)
        }
        var infos: [TrackInfo] = []
        for (index, track) in tracks.enumerated() {
            let (descriptions, timeRange) = try await track.load(.formatDescriptions, .timeRange)
            let basic = descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            infos.append(
                TrackInfo(
                    index: index,
                    channels: Int(basic?.mChannelsPerFrame ?? 0),
                    sampleRate: basic?.mSampleRate ?? 0,
                    duration: timeRange.duration.seconds
                )
            )
        }
        return infos
    }

    /// Reads one audio track, mixed down to mono and converted to `sampleRate`.
    ///
    /// - Parameters:
    ///   - track: Which audio track, from 0. Most files have one.
    ///   - timeRange: Only this stretch of the file, in seconds of its own time. Nil reads it all.
    public static func readMono(_ url: URL, track: Int = 0, sampleRate: Double = 48_000, timeRange: TimeRange? = nil) async throws -> AudioSamples {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw AudioKitError.unreadable(url, error.localizedDescription)
        }
        guard !tracks.isEmpty else { throw AudioKitError.noAudioTrack(url) }
        guard tracks.indices.contains(track) else {
            throw AudioKitError.trackOutOfRange(url, requested: track, available: tracks.count)
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AudioKitError.unreadable(url, error.localizedDescription)
        }
        if let timeRange {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: max(0, timeRange.start), preferredTimescale: 48_000),
                                           end: CMTime(seconds: max(0, timeRange.end), preferredTimescale: 48_000))
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ]
        let output = AVAssetReaderTrackOutput(track: tracks[track], outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw AudioKitError.unreadable(url, "AVFoundation can't convert this track to mono \(Int(sampleRate)) Hz.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioKitError.unreadable(url, reader.error?.localizedDescription ?? "Reading didn't start.")
        }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            let status = samples.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferCopyDataBytes(
                    block,
                    atOffset: 0,
                    dataLength: count * MemoryLayout<Float>.size,
                    destination: base.advanced(by: start * MemoryLayout<Float>.size)
                )
            }
            guard status == kCMBlockBufferNoErr else {
                throw AudioKitError.unreadable(url, "Couldn't copy audio data (\(status)).")
            }
        }
        if reader.status == .failed {
            throw AudioKitError.unreadable(url, reader.error?.localizedDescription ?? "Reading failed.")
        }
        return AudioSamples(samples: samples, sampleRate: sampleRate)
    }
}

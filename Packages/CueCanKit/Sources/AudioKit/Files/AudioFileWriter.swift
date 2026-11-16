import AVFoundation
import Foundation

/// Writes mono audio to a WAV file.
public enum AudioFileWriter {
    /// How samples are stored in the file.
    public enum Encoding: Sendable {
        /// 32-bit float: lossless, and keeps anything above 0 dBFS.
        case float32
        /// 24-bit integer: plays everywhere, and clips anything above 0 dBFS.
        case int24
        /// 16-bit integer, for APIs that accept nothing else, such as Apple's `SpeechDetector`.
        case int16

        var bitDepth: Int {
            switch self {
            case .float32: 32
            case .int24: 24
            case .int16: 16
            }
        }
    }

    public static func writeWAV(_ audio: AudioSamples, to url: URL, encoding: Encoding = .float32) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: encoding.bitDepth,
            AVLinearPCMIsFloatKey: encoding == .float32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Always start from a fresh file.
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(
                forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false
            )
            let chunk = 65_536
            var offset = 0
            while offset < audio.samples.count {
                let count = min(chunk, audio.samples.count - offset)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                    let channel = buffer.floatChannelData?[0]
                else {
                    throw AudioKitError.couldNotWrite(url, "Couldn't allocate an audio buffer.")
                }
                audio.samples.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress { channel.update(from: base.advanced(by: offset), count: count) }
                }
                buffer.frameLength = AVAudioFrameCount(count)
                try file.write(from: buffer)
                offset += count
            }
        } catch let error as AudioKitError {
            throw error
        } catch {
            throw AudioKitError.couldNotWrite(url, error.localizedDescription)
        }
    }
}

import AVFoundation
import Foundation

/// Plays the edit's sound through its audio mix, faster than real time, into mono samples for the
/// Loudness stage. Everything is mono: the voice, and system audio mixed down with it.
public enum AudioMixRenderer {
    public static let sampleRate = 48_000.0

    public static func render(_ built: BuiltComposition) async throws -> [Float] {
        try Task.checkCancellation()
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return [] }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: built.composition)
        } catch {
            throw RenderError.exportFailed("Couldn't read the edit's sound: \(error.localizedDescription)")
        }
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
            ]
        )
        output.audioMix = built.audioMix
        output.audioTimePitchAlgorithm = CompositionBuilder.pitchAlgorithm
        reader.add(output)
        guard reader.startReading() else {
            throw RenderError.exportFailed("Couldn't read the edit's sound: \(reader.error?.localizedDescription ?? "unknown error")")
        }
        defer { reader.cancelReading() }

        var samples: [Float] = []
        samples.reserveCapacity(Int(built.timeline.duration * sampleRate) + 1)
        while true {
            try Task.checkCancellation()
            guard let buffer = output.copyNextSampleBuffer() else { break }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { bytes in
                if let base = bytes.baseAddress { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base) }
            }
            samples.append(contentsOf: chunk)
        }
        if reader.status == .failed {
            throw RenderError.exportFailed("Couldn't read the edit's sound: \(reader.error?.localizedDescription ?? "unknown error")")
        }
        // The edit's exact length, so the sound ends with the picture.
        let length = Int((built.timeline.duration * sampleRate).rounded())
        if samples.count > length { samples.removeLast(samples.count - length) }
        return samples
    }
}

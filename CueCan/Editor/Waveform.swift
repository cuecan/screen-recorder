import AVFoundation
import Foundation
import ProjectKit

/// A mic's loudness over its source's time, for the audio lane: the peak of each short stretch.
nonisolated struct Waveform: Sendable {
    /// Peaks per second.
    static let rate = 50.0
    /// Measured linear peaks, from source time `start`, before the clip's level or display scaling.
    let peaks: [Float]
    let start: TimeInterval
    /// The same peaks in dB, for finding dips to snap to (docs/decisions.md, 74).
    let envelope: SoundEnvelope

    /// The peak around a source time, from 0 to 1.
    func peak(at time: TimeInterval) -> Float {
        let index = Int(((time - start) * Self.rate).rounded(.down))
        return peaks.indices.contains(index) ? peaks[index] : 0
    }

    /// The loudest peak in a stretch of source time.
    func peak(from: TimeInterval, to: TimeInterval) -> Float {
        let first = max(0, Int(((from - start) * Self.rate).rounded(.down)))
        let last = min(peaks.count - 1, Int(((to - start) * Self.rate).rounded(.up)))
        guard first <= last else { return 0 }
        return peaks[first...last].max() ?? 0
    }

    /// Reads a file's sound as mono and keeps its peaks. Nil if it can't be read.
    static func load(_ url: URL, startOffset: TimeInterval) async -> Waveform? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
            let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        let sampleRate = 8_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        let perPeak = Int(sampleRate / rate)
        var peaks: [Float] = []
        var current: Float = 0
        var count = 0
        while !Task.isCancelled, let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { bytes in
                if let base = bytes.baseAddress { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base) }
            }
            for sample in samples {
                current = max(current, abs(sample))
                count += 1
                if count == perPeak {
                    peaks.append(current)
                    current = 0
                    count = 0
                }
            }
        }
        guard !Task.isCancelled, reader.status != .failed else { return nil }
        if count > 0 { peaks.append(current) }
        let decibels = peaks.map { Double(20 * log10(max($0, 1e-6))) }
        return Waveform(peaks: peaks, start: startOffset,
                        envelope: SoundEnvelope(levels: decibels, frameDuration: 1 / rate, start: startOffset))
    }
}

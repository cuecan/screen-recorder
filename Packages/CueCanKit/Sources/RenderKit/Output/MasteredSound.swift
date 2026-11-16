import AVFoundation
import Foundation

/// The same final mono mix for exports and normalized preview, independent of video encoding.
public enum MasteredSound {
    /// Writes the mastered mix. False when the composition has no sound tracks.
    public static func writeMix(of built: BuiltComposition, to url: URL, using mastering: Exporter.Mastering) async throws -> Bool {
        let mix = try await AudioMixRenderer.render(built)
        guard !mix.isEmpty else { return false }
        let samples = try await mastering(mix, AudioMixRenderer.sampleRate)
        try Task.checkCancellation()
        guard samples.count == mix.count else { throw RenderError.exportFailed("Normalizing changed the sound's length. Try again.") }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioMixRenderer.sampleRate, channels: 1) else {
            throw RenderError.exportFailed("Couldn't prepare the normalized sound.")
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var offset = 0
        while offset < samples.count {
            try Task.checkCancellation()
            let count = min(65_536, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)), let channel = buffer.floatChannelData?[0] else {
                throw RenderError.exportFailed("Couldn't hold the normalized sound.")
            }
            samples.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { channel.update(from: base.advanced(by: offset), count: count) }
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            offset += count
        }
        return true
    }

    /// Independent pictures and one unity-gain mastered sound track. The original stays safe to play.
    public static func replacingSound(in original: BuiltComposition, with url: URL) async throws -> BuiltComposition {
        try Task.checkCancellation()
        let built = try original.copyForReading()
        for track in built.composition.tracks(withMediaType: .audio) { built.composition.removeTrack(track) }
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first,
              let lane = built.composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw RenderError.exportFailed("Couldn't add the normalized sound.") }
        let duration = try await asset.load(.duration)
        try Task.checkCancellation()
        try lane.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, built.composition.duration)), of: source, at: .zero)
        return BuiltComposition(composition: built.composition, videoComposition: built.videoComposition,
                                audioMix: AVMutableAudioMix(), timeline: built.timeline, panels: built.panels, audioTrackIDs: [lane.trackID])
    }
}

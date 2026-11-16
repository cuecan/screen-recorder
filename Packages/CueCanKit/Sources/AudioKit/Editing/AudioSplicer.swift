import Foundation
import ProjectKit

/// Joins stretches of one recording end to end: a quick way to hear an edit's cut points without
/// building a composition.
///
/// Each stretch fades in and out over a few milliseconds so a join never clicks. The stretches aren't
/// overlapped, so every join lasts exactly as long as the edit says.
public enum AudioSplicer {
    /// - Parameters:
    ///   - ranges: The stretches of `audio` to play, in order.
    ///   - fade: How long each stretch fades in and out.
    ///   - gap: Silence to put between stretches. Zero joins them directly.
    public static func splice(
        _ audio: AudioSamples,
        ranges: [TimeRange],
        fade: TimeInterval = 0.004,
        gap: TimeInterval = 0
    ) -> AudioSamples {
        let fadeLength = max(0, Int((fade * audio.sampleRate).rounded()))
        let gapSamples = [Float](repeating: 0, count: max(0, Int((gap * audio.sampleRate).rounded())))
        var output: [Float] = []
        for (position, range) in ranges.enumerated() {
            if position > 0 { output.append(contentsOf: gapSamples) }
            var piece = audio.slice(range).samples
            let ramp = min(fadeLength, piece.count / 2)
            if ramp > 0 {
                for index in 0..<ramp {
                    let factor = Float(index) / Float(ramp)
                    piece[index] *= factor
                    piece[piece.count - 1 - index] *= factor
                }
            }
            output.append(contentsOf: piece)
        }
        return AudioSamples(samples: output, sampleRate: audio.sampleRate)
    }
}

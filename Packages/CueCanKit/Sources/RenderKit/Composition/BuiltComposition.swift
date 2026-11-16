import AVFoundation
import Foundation
import ProjectKit

/// An edit as a composition, ready to play, grab stills from or export, in one output shape or several
/// side by side.
///
/// AVFoundation's composition objects aren't `Sendable`. Build one, then use it from one task at a time.
public final class BuiltComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVVideoComposition
    public let audioMix: AVAudioMix
    public let timeline: EditTimeline
    /// Each output and where it is in the composition's frame, left to right.
    public let panels: [(output: OutputShape, rect: CGRect)]
    /// Every composition track holding sound, mixed by ``audioMix``.
    public let audioTrackIDs: [CMPersistentTrackID]

    init(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition,
        audioMix: AVAudioMix,
        timeline: EditTimeline,
        panels: [(output: OutputShape, rect: CGRect)],
        audioTrackIDs: [CMPersistentTrackID]
    ) {
        self.composition = composition
        self.videoComposition = videoComposition
        self.audioMix = audioMix
        self.timeline = timeline
        self.panels = panels
        self.audioTrackIDs = audioTrackIDs
    }

    /// The first output: the only one, for an export or a still.
    public var output: OutputShape { panels.first?.output ?? .landscape }

    /// Where an output is in the frame.
    public func rect(of output: OutputShape) -> CGRect? {
        panels.first { $0.output == output }?.rect
    }

    /// Independent composition objects for a background reader while the original plays. Media files
    /// and immutable instructions are shared; mutable composition and compositor configuration aren't.
    public func copyForReading() throws -> BuiltComposition {
        guard let composition = composition.mutableCopy() as? AVMutableComposition,
              let video = videoComposition.copy() as? AVVideoComposition,
              let audio = audioMix.mutableCopy() as? AVMutableAudioMix
        else { throw RenderError.exportFailed("Couldn't prepare the preview's picture.") }
        return BuiltComposition(composition: composition, videoComposition: video, audioMix: audio,
                                timeline: timeline, panels: panels, audioTrackIDs: audioTrackIDs)
    }

    /// A player item that plays the edit exactly as it exports.
    @MainActor
    public func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        item.audioTimePitchAlgorithm = CompositionBuilder.pitchAlgorithm
        return item
    }

    /// Where each clip starts on the timeline: the cuts.
    public var cutTimes: [TimeInterval] {
        timeline.clips.map(\.timeline.start)
    }
}

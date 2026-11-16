import AVFoundation
import Foundation
import ProjectKit

/// Identifies the resolved sound and its automation without including layouts or picture size.
/// A visual edit can reuse an already mastered preview; new media, timing, levels or mastering cannot.
public enum PreviewSoundKey {
    public static func make(for built: BuiltComposition, target: Double, ceiling: Double) throws -> Data {
        let tracks = built.composition.tracks(withMediaType: .audio).map { track in
            track.segments.map { segment in
                Segment(file: segment.sourceURL, sourceTrack: segment.sourceTrackID,
                        source: Range(segment.timeMapping.source), target: Range(segment.timeMapping.target),
                        modification: segment.sourceURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate })
            }
        }
        let clips = built.timeline.clips.map { placed in
            ClipSound(time: placed.timeline, voice: placed.clip.voiceLevel, system: placed.clip.systemAudioLevel,
                      startsAtSplit: placed.clip.startsAtSplit)
        }
        let overlays = built.timeline.overlays.filter { $0.overlay.playsSound }.map {
            OverlaySound(time: $0.timeline, level: $0.overlay.level)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Key(tracks: tracks, clips: clips, overlays: overlays, target: target, ceiling: ceiling))
    }

    private struct Key: Encodable {
        let tracks: [[Segment]]
        let clips: [ClipSound]
        let overlays: [OverlaySound]
        let target: Double
        let ceiling: Double
    }
    private struct Segment: Encodable {
        let file: URL?
        let sourceTrack: CMPersistentTrackID
        let source: Range
        let target: Range
        let modification: Date?
    }
    private struct Range: Encodable {
        let start: Time
        let duration: Time
        init(_ range: CMTimeRange) { start = Time(range.start); duration = Time(range.duration) }
    }
    private struct Time: Encodable {
        let value: Int64
        let scale: Int32
        let flags: UInt32
        let epoch: Int64
        init(_ time: CMTime) { value = time.value; scale = time.timescale; flags = time.flags.rawValue; epoch = time.epoch }
    }
    private struct ClipSound: Encodable {
        let time: TimeRange
        let voice: Double
        let system: Double
        let startsAtSplit: Bool
    }
    private struct OverlaySound: Encodable {
        let time: TimeRange
        let level: Double
    }
}

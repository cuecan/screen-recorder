import Foundation

/// The edit laid out on the edited timeline: where each clip and each overlay plays, and the stretches
/// between changes that the compositor draws one way.
public struct EditTimeline: Sendable {
    /// A main-track clip on the timeline.
    public typealias PlacedClip = Edit.TimelinePlacement

    /// One stretch of an overlay on the timeline: where its words or its source time play. Words that play
    /// in two places, with something else between, give two stretches, so the overlay never covers the
    /// other clip.
    public struct PlacedOverlay: Sendable, Equatable {
        public var overlay: Overlay
        public var timeline: TimeRange
        /// The overlay's own media time at the start of this stretch. It keeps pace with the timeline, so a
        /// later stretch picks up where the last left off.
        public var mediaStart: TimeInterval

        /// The overlay's own time at a timeline time.
        public func mediaTime(at time: TimeInterval) -> TimeInterval {
            mediaStart + (time - timeline.start)
        }
    }

    /// A stretch of the timeline with one clip and the same overlays showing.
    public struct Segment: Sendable, Equatable {
        public var timeline: TimeRange
        /// Index into ``EditTimeline/clips``.
        public var clipIndex: Int
        /// Indices into ``EditTimeline/overlays``, back to front.
        public var overlayIndices: [Int]
    }

    public let clips: [PlacedClip]
    public let overlays: [PlacedOverlay]
    public let segments: [Segment]

    public var duration: TimeInterval { clips.last?.timeline.end ?? 0 }

    /// Lays out an edit. Overlays whose words aren't played anywhere are left out.
    public init(edit: Edit, transcripts: TranscriptIndex, snapping: SnapSettings = .default) {
        let clips = edit.placements
        self.clips = clips

        // Later overlays are drawn over earlier ones where they overlap.
        let overlays = edit.overlays.flatMap { overlay in
            edit.timelinePieces(of: overlay, transcripts: transcripts, snapping: snapping).map {
                PlacedOverlay(overlay: overlay, timeline: $0.timeline, mediaStart: $0.mediaStart)
            }
        }
        self.overlays = overlays

        var cuts = Set(clips.flatMap { [$0.timeline.start, $0.timeline.end] })
        for item in overlays { cuts.formUnion([item.timeline.start, item.timeline.end]) }
        let times = cuts.sorted()
        var segments: [Segment] = []
        var clipIndex = 0
        for (start, end) in zip(times, times.dropFirst()) where end > start {
            while clipIndex < clips.count - 1, clips[clipIndex].timeline.end <= start { clipIndex += 1 }
            guard clipIndex < clips.count, clips[clipIndex].timeline.start <= start else { continue }
            let middle = (start + end) / 2
            let covering = overlays.indices.filter { overlays[$0].timeline.start <= middle && middle < overlays[$0].timeline.end }
            segments.append(Segment(timeline: TimeRange(start: start, end: end), clipIndex: clipIndex, overlayIndices: covering))
        }
        self.segments = segments
    }

    /// Every place on the timeline a moment of a source plays. A moment can play more than once if Claude
    /// used the same words twice.
    public func timelineTimes(of time: TimeInterval, in source: SourceID) -> [TimeInterval] {
        clips.compactMap { placed in
            guard placed.clip.source == source else { return nil }
            let played = placed.clip.playedRange
            guard time >= played.start, time < played.end else { return nil }
            return placed.timelineTime(ofSourceTime: time)
        }
    }

    /// The clip playing at a timeline time.
    public func clipIndex(at time: TimeInterval) -> Int? {
        clips.firstIndex { $0.timeline.start <= time && time < $0.timeline.end }
    }
}

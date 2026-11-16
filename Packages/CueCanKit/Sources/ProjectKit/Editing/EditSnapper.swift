import Foundation

/// Snapping for the editor's blade and dragged edges (docs/decisions.md, 56 and 74): a convenience, not a
/// rule of the model. While it's on, times stick to the edges of silences (where a cut by id would land, just
/// before the next word or just after the last one fades), to the moments the screen goes still, to clip edges
/// and the playhead. With none of those in reach, they stick to the bottom of a dip in the voice's loudness,
/// such as the gap between two words or two syllables. Word times aren't snap points: they come from the
/// transcription model and can be off, while silences and dips come from the audio.
public struct EditSnapper: Sendable {
    /// Points of source time to stick to, by source.
    public let points: [SourceID: [TimeInterval]]
    private let targets: [SourceID: [TimeInterval: Target]]
    /// Each source's voice loudness, for dips.
    public let envelopes: [SourceID: SoundEnvelope]

    public init(transcripts: TranscriptIndex, stillMoments: [SourceID: [TimeInterval]] = [:],
                envelopes: [SourceID: SoundEnvelope] = [:], snapping: SnapSettings = .default) {
        var points: [SourceID: [TimeInterval]] = [:]
        var targets: [SourceID: [TimeInterval: Target]] = [:]
        for (source, transcript) in transcripts.transcripts {
            let snapper = CutPointSnapper(transcript: transcript, settings: snapping)
            var kinds: [TimeInterval: Target] = [:]
            func add(_ time: TimeInterval, _ target: Target) { kinds[(time * 1000).rounded() / 1000] = target }
            for (index, item) in transcript.items.enumerated() {
                guard case .silence = item else { continue }
                add(snapper.boundary(before: index), .silenceEdge)
                add(snapper.boundary(before: index + 1), .silenceEdge)
            }
            for moment in stillMoments[source] ?? [] { add(moment, .screenStill) }
            targets[source] = kinds
            points[source] = kinds.keys.sorted()
        }
        for (source, moments) in stillMoments where points[source] == nil {
            points[source] = moments.sorted()
            targets[source] = Dictionary(moments.map { ($0, .screenStill) }, uniquingKeysWith: { first, _ in first })
        }
        self.points = points
        self.targets = targets
        self.envelopes = envelopes
    }

    /// What a snapped time stuck to.
    public enum Target: Equatable, Sendable {
        /// Where a silence meets a word, padded as a cut by id is.
        case silenceEdge
        /// The bottom of a dip in the voice's loudness.
        case quietPoint
        case screenStill, clipEdge, playhead
    }

    /// The edited-timeline time to use for `time`: the nearest point within `tolerance` seconds of the
    /// timeline, else the bottom of a dip within it in the clip under `time`, else `time` itself.
    public func snap(_ time: TimeInterval, in edit: Edit, tolerance: TimeInterval, extra: [TimeInterval] = []) -> (time: TimeInterval, target: Target?) {
        var best: (time: TimeInterval, target: Target)?
        func consider(_ candidate: TimeInterval, _ target: Target) {
            let distance = abs(candidate - time)
            guard distance <= tolerance, distance < abs((best?.time ?? .infinity) - time) else { return }
            best = (candidate, target)
        }
        let placements = edit.placements
        for placed in placements {
            consider(placed.timeline.start, .clipEdge)
            consider(placed.timeline.end, .clipEdge)
            guard placed.timeline.start - tolerance <= time, time <= placed.timeline.end + tolerance else { continue }
            let played = placed.clip.playedRange
            for point in points[placed.clip.source] ?? [] where point > played.start && point < played.end {
                consider(placed.timelineTime(ofSourceTime: point), targets[placed.clip.source]?[point] ?? .silenceEdge)
            }
        }
        for candidate in extra { consider(candidate, .playhead) }
        if let best { return (best.time, best.target) }

        if let placed = placements.first(where: { $0.timeline.start <= time && time < $0.timeline.end }),
            let dip = dip(in: placed, near: time, tolerance: tolerance)
        {
            return (dip, .quietPoint)
        }
        return (time, nil)
    }

    /// A source time to use for a dragged edge of a clip from `source`: the nearest point within `tolerance`
    /// seconds of source time, else the bottom of a dip within it. Nil when nothing's in reach.
    public func snap(sourceTime time: TimeInterval, in source: SourceID, tolerance: TimeInterval) -> (time: TimeInterval, target: Target)? {
        if let nearest = points[source]?.min(by: { abs($0 - time) < abs($1 - time) }), abs(nearest - time) <= tolerance {
            return (nearest, targets[source]?[nearest] ?? .silenceEdge)
        }
        if let dip = envelopes[source]?.dip(in: TimeRange(start: time - tolerance, end: time + tolerance), near: time) {
            return (dip, .quietPoint)
        }
        return nil
    }

    /// The bottom of a dip in the clip's own voice within `tolerance` of a timeline time, as a timeline time.
    private func dip(in placed: Edit.TimelinePlacement, near time: TimeInterval, tolerance: TimeInterval) -> TimeInterval? {
        // A clip playing another source's voice has no envelope in its own source's time.
        guard placed.clip.audio == nil, let envelope = envelopes[placed.clip.source] else { return nil }
        let window = TimeRange(start: max(placed.timeline.start, time - tolerance), end: min(placed.timeline.end, time + tolerance))
        let source = TimeRange(start: placed.sourceTime(at: window.start), end: placed.sourceTime(at: window.end))
        guard let dip = envelope.dip(in: source, near: placed.sourceTime(at: time)) else { return nil }
        return placed.timelineTime(ofSourceTime: dip)
    }
}

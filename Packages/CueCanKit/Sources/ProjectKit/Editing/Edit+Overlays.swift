import Foundation

/// Placing pictures and clips on top of the main track (docs/decisions.md, 54), the operations behind
/// `place_broll` and the overlay lane's gestures.
extension Edit {
    /// Shows a picture or a clip over a range of the main track's words.
    @discardableResult
    public mutating func placeOverlay(
        _ media: Overlay.Media,
        over range: ItemRange,
        placement: Overlay.Placement = .coversFrame,
        sourceIn: TimeInterval = 0,
        muted: Bool = true,
        transcripts: TranscriptIndex
    ) throws(EditError) -> Overlay {
        let transcript = try transcripts.transcript(containing: range)
        _ = try CutPointSnapper(transcript: transcript).indices(of: range)
        let overlay = Overlay(id: makeClipID(), media: media, sourceIn: sourceIn, over: .words(range), placement: placement, isMuted: muted)
        overlays.append(overlay)
        return overlay
    }

    /// Shows a picture or a clip over a stretch of the edited timeline. It's anchored to the source time
    /// that plays there, so it moves with later cuts. A stretch that crosses a cut is anchored to its first
    /// clip's source.
    @discardableResult
    public mutating func placeOverlay(
        _ media: Overlay.Media,
        overTimeline range: TimeRange,
        placement: Overlay.Placement = .coversFrame,
        sourceIn: TimeInterval = 0,
        muted: Bool = true
    ) throws(EditError) -> Overlay {
        let overlay = Overlay(id: makeClipID(), media: media, sourceIn: sourceIn, over: try anchor(forTimeline: range), placement: placement, isMuted: muted)
        overlays.append(overlay)
        return overlay
    }

    /// The source time a stretch of the timeline plays, as an overlay's anchor: from the first clip's source.
    func anchor(forTimeline range: TimeRange) throws(EditError) -> Overlay.Anchor {
        guard range.end > range.start else { throw .invalidTimeRange(range) }
        let pieces = sourcePieces(of: range)
        guard let first = pieces.first else { throw .timeOutsideEdit(range.start, duration: duration) }
        let sameSource = pieces.filter { $0.source == first.source }
        let end = sameSource.map(\.range.end).max() ?? first.range.end
        return .time(source: first.source, range: TimeRange(start: first.range.start, end: max(end, first.range.start + Self.sliver)))
    }

    /// Moves or stretches an overlay over other words.
    public mutating func moveOverlay(_ id: ClipID, over range: ItemRange, transcripts: TranscriptIndex) throws(EditError) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { throw .unknownOverlay(id) }
        let transcript = try transcripts.transcript(containing: range)
        _ = try CutPointSnapper(transcript: transcript).indices(of: range)
        overlays[index].over = .words(range)
    }

    /// Moves or stretches an overlay over another stretch of the timeline.
    public mutating func moveOverlay(_ id: ClipID, overTimeline range: TimeRange) throws(EditError) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { throw .unknownOverlay(id) }
        overlays[index].over = try anchor(forTimeline: range)
    }

    /// Changes an overlay in place: where it sits, its sound, what it shows.
    public mutating func updateOverlay(_ id: ClipID, _ change: (inout Overlay) -> Void) throws(EditError) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { throw .unknownOverlay(id) }
        change(&overlays[index])
    }

    public mutating func removeOverlay(_ id: ClipID) throws(EditError) {
        guard overlays.contains(where: { $0.id == id }) else { throw .unknownOverlay(id) }
        overlays.removeAll { $0.id == id }
    }

    /// The stretches of the timeline an overlay shows over, each with the overlay's own time at its start.
    /// Words that play in two places, with something else between, give two stretches.
    public func timelinePieces(of overlay: Overlay, transcripts: TranscriptIndex, snapping: SnapSettings = .default) -> [(timeline: TimeRange, mediaStart: TimeInterval)] {
        let source: SourceID
        let range: TimeRange
        switch overlay.over {
        case .words(let words):
            guard let transcript = try? transcripts.transcript(containing: words),
                let time = try? CutPointSnapper(transcript: transcript, settings: snapping).timeRange(for: words)
            else { return [] }
            source = transcript.source
            range = time
        case .time(let anchorSource, let time):
            source = anchorSource
            range = time
        }
        // The overlay's own media keeps pace with the timeline, so a later stretch picks up where it left off.
        var elapsed: TimeInterval = 0
        return timelinePieces(of: range, in: source).map { piece in
            defer { elapsed += piece.timeline.duration }
            return (piece.timeline, overlay.sourceIn + elapsed)
        }
    }
}

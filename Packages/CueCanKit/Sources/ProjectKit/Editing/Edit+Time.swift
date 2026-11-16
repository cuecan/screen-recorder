import Foundation

/// Cutting by exact time, for cuts between two words, at a breath, or inside a stretch with no words, such as
/// a 40-second wait on screen (docs/decisions.md, 11 and 56). The creator's gestures and Claude's time-based
/// tools both land here.
///
/// Times on the edited timeline go through each clip's speed, so a second of a 4× clip is four seconds of
/// its source.
extension Edit {
    /// A main-track clip and where it plays on the edited timeline.
    public struct TimelinePlacement: Equatable, Sendable {
        public var index: Int
        public var clip: Clip
        public var timeline: TimeRange

        public init(index: Int = 0, clip: Clip, timeline: TimeRange) {
            self.index = index
            self.clip = clip
            self.timeline = timeline
        }

        /// The source time playing at a timeline time inside this clip.
        public func sourceTime(at time: TimeInterval) -> TimeInterval {
            clip.sourceTime(atOffset: time - timeline.start)
        }

        /// The timeline time a moment of the clip's source plays at.
        public func timelineTime(ofSourceTime time: TimeInterval) -> TimeInterval {
            timeline.start + clip.offset(ofSourceTime: time)
        }
    }

    /// Every main-track clip with where it plays, back to back.
    public var placements: [TimelinePlacement] {
        var position: TimeInterval = 0
        return main.enumerated().map { index, clip in
            defer { position += clip.duration }
            return TimelinePlacement(index: index, clip: clip, timeline: TimeRange(start: position, end: position + clip.duration))
        }
    }

    /// The clip playing at a timeline time. The very end of the edit belongs to the last clip.
    public func placement(at time: TimeInterval) -> TimelinePlacement? {
        let all = placements
        if let last = all.last, abs(time - last.timeline.end) < Self.sliver { return last }
        return all.first { $0.timeline.start <= time && time < $0.timeline.end }
    }

    /// The source and source time playing at a timeline time.
    public func sourceTime(at time: TimeInterval) -> (source: SourceID, time: TimeInterval)? {
        placement(at: time).map { ($0.clip.source, $0.sourceTime(at: time)) }
    }

    /// Every stretch of the timeline that plays part of a stretch of one source's time, in timeline order,
    /// each with the source time it starts at. Stretches that meet and play on from each other are joined.
    public func timelinePieces(of range: TimeRange, in source: SourceID) -> [(timeline: TimeRange, sourceStart: TimeInterval)] {
        var pieces: [(timeline: TimeRange, sourceStart: TimeInterval)] = []
        for placed in placements where placed.clip.source == source {
            let played = placed.clip.playedRange
            let from = max(range.start, played.start)
            let to = min(range.end, played.end)
            guard to > from else { continue }
            let timeline = TimeRange(start: placed.timelineTime(ofSourceTime: from), end: placed.timelineTime(ofSourceTime: to))
            if let last = pieces.last, abs(last.timeline.end - timeline.start) < 1e-9,
                placed.index > 0, abs(main[placed.index - 1].playedRange.end - from) < 1e-9
            {
                pieces[pieces.count - 1].timeline.end = timeline.end
            } else {
                pieces.append((timeline, from))
            }
        }
        return pieces
    }

    /// The source time each clip plays within a stretch of the timeline.
    public func sourcePieces(of range: TimeRange) -> [(index: Int, source: SourceID, range: TimeRange)] {
        placements.compactMap { placed in
            let from = max(range.start, placed.timeline.start)
            let to = min(range.end, placed.timeline.end)
            guard to - from > Self.sliver else { return nil }
            return (placed.index, placed.clip.source, TimeRange(start: placed.sourceTime(at: from), end: placed.sourceTime(at: to)))
        }
    }

    // MARK: - Cutting by time

    /// Removes a stretch of the edited timeline, such as the creator's selection or most of a wait on screen.
    /// Only what plays there goes; the same source time played elsewhere stays. The rest closes up: there's
    /// never a gap on the main track (docs/decisions.md, 56).
    ///
    /// - Parameter byHand: Marks the edges it makes as placed by hand.
    /// - Returns: How many seconds the edit got shorter.
    @discardableResult
    public mutating func cut(timeline range: TimeRange, byHand: Bool = false) throws(EditError) -> TimeInterval {
        guard range.end > range.start else { throw .invalidTimeRange(range) }
        let before = duration
        guard range.start < before - Self.sliver, range.end > Self.sliver else { throw .timeOutsideEdit(range.start, duration: before) }
        let pieces = sourcePieces(of: range)
        // From the last clip back, so the earlier indices stay right.
        for piece in pieces.reversed() {
            let clip = main[piece.index]
            let remaining = clip.playedRange.subtracting(piece.range).filter { $0.duration > Self.sliver }
            var replacements: [Clip] = []
            for (offset, part) in remaining.enumerated() {
                let copy = offset == 0 ? clip : clip.withID(makeClipID())
                replacements.append(copy.playing(part, byHand: byHand))
            }
            main.replaceSubrange(piece.index...piece.index, with: replacements)
        }
        return before - duration
    }

    /// Removes a stretch of one source's time from wherever the main track plays it, like a cut by word id
    /// but at exact times.
    @discardableResult
    public mutating func cut(source: SourceID, range: TimeRange, byHand: Bool = false) throws(EditError) -> TimeInterval {
        guard range.end > range.start else { throw .invalidTimeRange(range) }
        let before = duration
        remove(range, from: source, byHand: byHand)
        return before - duration
    }

    /// Puts back a stretch of one source's time, next to the clips it was cut from.
    @discardableResult
    public mutating func keep(source: SourceID, range: TimeRange, sourceDuration: TimeInterval? = nil, byHand: Bool = false) throws(EditError) -> TimeInterval {
        guard range.end > range.start else { throw .invalidTimeRange(range) }
        let clamped = TimeRange(start: max(0, range.start), end: min(range.end, sourceDuration ?? range.end))
        guard clamped.end > clamped.start else { throw .invalidTimeRange(range) }
        let before = duration
        restore(clamped, from: source, byHand: byHand)
        return duration - before
    }

    /// Removes one clip from the main track. The rest closes up.
    public mutating func removeClip(_ clipID: ClipID) throws(EditError) {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        main.remove(at: index)
        if index < main.count { main[index].startsAtSplit = false }
    }

    /// Divides the clip playing at a timeline time in two there, removing nothing: the blade.
    @discardableResult
    public mutating func split(at time: TimeInterval, byHand: Bool = false) throws(EditError) -> (first: Clip, second: Clip) {
        guard let placed = placement(at: time) else { throw .timeOutsideEdit(time, duration: duration) }
        let sourceTime = placed.sourceTime(at: time)
        let played = placed.clip.playedRange
        guard sourceTime > played.start + Self.minimumClipDuration, sourceTime < played.end - Self.minimumClipDuration else {
            throw .splitTooCloseToEdge(time, placed.clip.id)
        }
        return splitClip(at: placed.index, sourceTime: sourceTime, byHand: byHand)
    }

    /// Puts one edge of a clip at an exact source time: a trim inward, or, outward, bringing back what was
    /// cut. An edge put there by the creator is marked as placed by hand.
    ///
    /// - Parameters:
    ///   - sourceDuration: The clip's source length, so the edge stays inside the recording.
    ///   - rolling: Whether an edge moved outward at a join that rolls takes the neighbour's edge with it. The
    ///     editor's pointer passes false but for its Trim tool on a join, and the edge then stops at the join.
    @discardableResult
    public mutating func setEdge(
        _ edge: ClipEdge,
        of clipID: ClipID,
        to time: TimeInterval,
        sourceDuration: TimeInterval?,
        byHand: Bool = false,
        rolling: Bool = true
    ) throws(EditError) -> Clip {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        var clip = main[index]
        guard time >= -1e-9, time <= (sourceDuration ?? .infinity) + 1e-9 else { throw .edgeOutsideRecording(clipID) }
        var time = max(0, time)
        let rolls = rolling && isRollable(edge, of: clipID)
        if let limit = outwardLimit(edge, of: clipID, rolling: rolling) { time = edge == .start ? max(time, limit) : min(time, limit) }
        switch edge {
        case .start:
            clip.sourceIn = time
            clip.startNudge = 0
            clip.startPlacedByHand = byHand
        case .end:
            clip.sourceOut = time
            clip.endNudge = 0
            clip.endPlacedByHand = byHand
        }
        guard clip.playedRange.duration >= Self.minimumClipDuration else { throw .edgeLeavesTooLittle(clipID) }
        try settleJoin(edge, of: &clip, at: index, rolls: rolls, byHand: byHand)
        main[index] = clip
        return clip
    }

    // MARK: - Joins

    /// How close two edges must be to meet, in seconds.
    static let joinTolerance: TimeInterval = 1e-6

    /// Whether the clip at `index` and the next one meet with nothing cut between, from the same recording,
    /// as the two halves of a split do. Such a join rolls: moving either edge outward moves both, so the
    /// join moves and nothing plays twice. Trimming either one inward cuts, and then it no longer rolls.
    public func joinRolls(after index: Int) -> Bool {
        guard index >= 0, index + 1 < main.count else { return false }
        let (first, second) = (main[index], main[index + 1])
        return first.source == second.source && abs(first.playedRange.end - second.playedRange.start) < Self.joinTolerance
    }

    /// Whether an edge of a clip is at a join that rolls.
    public func isRollable(_ edge: ClipEdge, of clipID: ClipID) -> Bool {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { return false }
        return joinRolls(after: edge == .end ? index : index - 1)
    }

    /// The two clips that meet at an edge of a clip, when their join rolls: the earlier one and the later one.
    public func rollingPair(_ edge: ClipEdge, of clipID: ClipID) -> (before: Clip, after: Clip)? {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { return nil }
        let first = edge == .end ? index : index - 1
        return joinRolls(after: first) ? (main[first], main[first + 1]) : nil
    }

    /// The farthest an edge can move outward, in source time, when the clip next to it plays the same
    /// recording with a cut between them: up to where that clip's edge is, so nothing plays twice. Once
    /// they meet, the join rolls. Nil when nothing limits it, or it rolls.
    ///
    /// - Parameter rolling: False when the join isn't to roll: the edge then stops at the join itself.
    public func outwardLimit(_ edge: ClipEdge, of clipID: ClipID, rolling: Bool = true) -> TimeInterval? {
        guard let index = main.firstIndex(where: { $0.id == clipID }), !(rolling && isRollable(edge, of: clipID)) else { return nil }
        let clip = main[index]
        switch edge {
        case .start:
            guard index > 0, main[index - 1].source == clip.source else { return nil }
            let end = main[index - 1].playedRange.end
            return clip.playedRange.start >= end - Self.joinTolerance ? end : nil
        case .end:
            guard index + 1 < main.count, main[index + 1].source == clip.source else { return nil }
            let start = main[index + 1].playedRange.start
            return clip.playedRange.end <= start + Self.joinTolerance ? start : nil
        }
    }

    /// The source-time bounds a pointer trim can reach while preserving both clips at a rolling join.
    /// Tool operations still validate their exact requested time; a drag uses these bounds for feedback
    /// that stops where its eventual edit will stop, including the recording's ends.
    public func edgeRange(_ edge: ClipEdge, of clipID: ClipID, sourceDuration: TimeInterval?, rolling: Bool = true) -> ClosedRange<TimeInterval>? {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { return nil }
        let played = main[index].playedRange
        // Keep subtraction at the minimum duration on its valid side of floating-point rounding.
        var lower = edge == .start ? 0 : (played.start + Self.minimumClipDuration).nextUp
        var upper = edge == .start ? (played.end - Self.minimumClipDuration).nextDown : sourceDuration ?? .infinity
        if let limit = outwardLimit(edge, of: clipID, rolling: rolling) {
            if edge == .start { lower = max(lower, limit) } else { upper = min(upper, limit) }
        }
        if rolling, isRollable(edge, of: clipID) {
            if edge == .start { lower = max(lower, (main[index - 1].playedRange.start + Self.minimumClipDuration).nextUp) }
            else { upper = min(upper, (main[index + 1].playedRange.end - Self.minimumClipDuration).nextDown) }
        }
        guard lower <= upper else { return nil }
        return lower...upper
    }

    /// After one edge of the clip at `index` moved: at a join that rolled, the neighbour's edge follows an
    /// edge moved outward into it; then the join is marked as playing on when the two meet, so the sound
    /// doesn't fade across it.
    ///
    /// - Parameter rolls: Whether the join rolled before the edge moved.
    mutating func settleJoin(_ edge: ClipEdge, of clip: inout Clip, at index: Int, rolls: Bool, byHand: Bool) throws(EditError) {
        switch edge {
        case .start:
            guard index > 0 else { return }
            var previous = main[index - 1]
            if rolls, clip.playedRange.start < previous.playedRange.end {
                previous.sourceOut = clip.playedRange.start
                previous.endNudge = 0
                if byHand { previous.endPlacedByHand = true }
                guard previous.playedRange.duration >= Self.minimumClipDuration else { throw .edgeLeavesTooLittle(previous.id) }
                main[index - 1] = previous
            }
            clip.startsAtSplit = previous.source == clip.source && abs(previous.playedRange.end - clip.playedRange.start) < Self.joinTolerance
        case .end:
            guard index + 1 < main.count else { return }
            var next = main[index + 1]
            if rolls, clip.playedRange.end > next.playedRange.start {
                next.sourceIn = clip.playedRange.end
                next.startNudge = 0
                if byHand { next.startPlacedByHand = true }
                guard next.playedRange.duration >= Self.minimumClipDuration else { throw .edgeLeavesTooLittle(next.id) }
            }
            next.startsAtSplit = next.source == clip.source && abs(clip.playedRange.end - next.playedRange.start) < Self.joinTolerance
            main[index + 1] = next
        }
    }

    /// Trims the clip at the playhead so its start or end is at the playhead (⌥[ and ⌥]).
    @discardableResult
    public mutating func trim(_ edge: ClipEdge, toTimeline time: TimeInterval, sourceDuration: TimeInterval?, byHand: Bool = false) throws(EditError) -> Clip {
        guard let placed = placement(at: time) else { throw .timeOutsideEdit(time, duration: duration) }
        return try setEdge(edge, of: placed.clip.id, to: placed.sourceTime(at: time), sourceDuration: sourceDuration, byHand: byHand)
    }
}

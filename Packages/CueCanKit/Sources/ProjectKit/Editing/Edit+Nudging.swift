import Foundation

/// Adjustments to the cut: moving one edge of a clip by frames, and splitting a clip in two without
/// removing anything, so each part can have its own layout. A nudge has no limit: clip edges are plain
/// source times, and snapping only helps pick them (docs/decisions.md, 56).
extension Edit {
    /// The least a clip can play after a nudge, in seconds.
    public static let minimumClipDuration: TimeInterval = 0.02

    /// Moves one edge of a clip, such as when the cut catches the start of a word.
    ///
    /// The nudge adds to any nudge already on that edge, and is kept as an offset from where the edge was
    /// put. Frames are converted to seconds by the caller, from the source's frame rate.
    ///
    /// - Parameters:
    ///   - seconds: In source time. Positive moves the edge later, negative earlier.
    ///   - byHand: Marks the edge as placed by hand, so broad passes leave it alone.
    ///   - rolling: Whether an edge nudged outward at a join that rolls takes the neighbour's with it
    ///     (``setEdge(_:of:to:sourceDuration:byHand:rolling:)``).
    @discardableResult
    public mutating func nudge(
        _ edge: ClipEdge,
        of clipID: ClipID,
        by seconds: TimeInterval,
        transcripts: TranscriptIndex,
        byHand: Bool = false,
        rolling: Bool = true
    ) throws(EditError) -> NudgeResult {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        var clip = main[index]
        let rolls = rolling && isRollable(edge, of: clipID)
        let limit = outwardLimit(edge, of: clipID, rolling: rolling)
        let total = (edge == .start ? clip.startNudge : clip.endNudge) + seconds
        switch edge {
        case .start:
            clip.startNudge = total
            if byHand { clip.startPlacedByHand = true }
            // Outward, it stops where the clip before it ends, so nothing plays twice.
            if let limit, clip.playedRange.start < limit { clip.startNudge += limit - clip.playedRange.start }
        case .end:
            clip.endNudge = total
            if byHand { clip.endPlacedByHand = true }
            if let limit, clip.playedRange.end > limit { clip.endNudge -= clip.playedRange.end - limit }
        }

        let played = clip.playedRange
        guard played.duration >= Self.minimumClipDuration else { throw .nudgeLeavesTooLittle(clipID) }
        let transcript = transcripts[clip.source]
        guard played.start >= 0, played.end <= (transcript?.audioDuration ?? .infinity) else {
            throw .nudgeOutsideRecording(clipID)
        }
        // At a join that rolls, the neighbour follows an edge nudged into it.
        try settleJoin(edge, of: &clip, at: index, rolls: rolls, byHand: byHand)
        main[index] = clip
        let edgeTime = edge == .start ? played.start : played.end
        let words = transcript?.words.filter { $0.start < edgeTime && edgeTime < $0.end }.map(\.id) ?? []
        return NudgeResult(clip: clip, edgeTime: edgeTime, wordsAtEdge: words)
    }

    /// Divides a clip in two just before a word, without removing anything: the two parts play on from each
    /// other, and each can have its own layout. The division lands where a cut before that word would.
    @discardableResult
    public mutating func split(
        _ clipID: ClipID,
        before word: WordID,
        transcripts: TranscriptIndex,
        snapping: SnapSettings = .default,
        byHand: Bool = false
    ) throws(EditError) -> (first: Clip, second: Clip) {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        let clip = main[index]
        let transcript = try transcripts.transcript(containing: ItemRange(.word(word)))
        guard transcript.source == clip.source, let wordIndex = transcript.index(of: .word(word)) else {
            throw .splitOutsideClip(word, clipID)
        }
        let time = CutPointSnapper(transcript: transcript, settings: snapping).boundary(before: wordIndex)
        let played = clip.playedRange
        guard time > played.start + Self.minimumClipDuration, time < played.end - Self.minimumClipDuration else {
            throw .splitOutsideClip(word, clipID)
        }

        return splitClip(at: index, sourceTime: time, byHand: byHand)
    }

    /// Divides the clip at `index` at a source time it plays, removing nothing.
    mutating func splitClip(at index: Int, sourceTime time: TimeInterval, byHand: Bool) -> (first: Clip, second: Clip) {
        let clip = main[index]
        let played = clip.playedRange
        let first = clip.playing(TimeRange(start: played.start, end: time), byHand: byHand)
        var second = clip.withID(makeClipID()).playing(TimeRange(start: time, end: played.end), byHand: byHand)
        second.startsAtSplit = true
        main[index] = first
        main.insert(second, at: index + 1)
        return (first, second)
    }
}

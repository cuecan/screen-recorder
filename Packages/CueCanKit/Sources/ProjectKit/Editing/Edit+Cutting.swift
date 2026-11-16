import Foundation

/// Cutting and keeping by word id: the operations behind the MCP tools `add_clip`, `cut`, `keep`,
/// `remove_silences` and `set_layout`. Cutting by time is in `Edit+Time.swift`.
///
/// Every operation turns ids into source time with ``CutPointSnapper``, so clip edges always land at the
/// boundaries between transcript items, inside real silences wherever there is one.
extension Edit {
    /// Pieces shorter than this, left over from floating-point arithmetic, are dropped.
    static let sliver: TimeInterval = 0.001

    /// Puts a range of words on the main track as a new clip.
    ///
    /// - Parameters:
    ///   - position: Where on the main track, from 0 (first) to the number of clips (last). Nil appends.
    @discardableResult
    public mutating func addClip(
        _ range: ItemRange,
        at position: Int? = nil,
        layout: Layout = .automatic,
        look: ClipLook? = nil,
        audio: ClipAudio? = nil,
        transcripts: TranscriptIndex,
        snapping: SnapSettings = .default
    ) throws(EditError) -> Clip {
        let transcript = try transcripts.transcript(containing: range)
        let time = try CutPointSnapper(transcript: transcript, settings: snapping).timeRange(for: range)
        let position = position ?? main.count
        guard (0...main.count).contains(position) else {
            throw .invalidPosition(position, clipCount: main.count)
        }
        let clip = Clip(
            id: makeClipID(),
            source: transcript.source,
            sourceIn: time.start,
            sourceOut: time.end,
            audio: audio,
            layout: layout,
            // Unless given, the clip it follows sets its look, or else the one it comes before.
            look: look ?? (position > 0 ? main[position - 1].look : main.first?.look) ?? ClipLook()
        )
        main.insert(clip, at: position)
        return clip
    }

    /// Removes a range of words and silences from wherever the main track plays them.
    ///
    /// - Returns: How many seconds the edit got shorter. Zero when the range isn't on the timeline, or is
    ///   too short to cut after padding.
    @discardableResult
    public mutating func cut(
        _ range: ItemRange,
        transcripts: TranscriptIndex,
        snapping: SnapSettings = .default,
        byHand: Bool = false
    ) throws(EditError) -> TimeInterval {
        let transcript = try transcripts.transcript(containing: range)
        let time = try CutPointSnapper(transcript: transcript, settings: snapping).timeRange(for: range)
        let before = duration
        remove(time, from: transcript.source, byHand: byHand)
        return before - duration
    }

    /// Puts back a range of words and silences that was cut, next to the clips it was cut from.
    ///
    /// Parts already on the timeline aren't added twice. A part that meets a clip of the same source
    /// extends it. Anything else becomes a new clip, placed after the clip that plays the source just
    /// before it.
    ///
    /// - Returns: How many seconds the edit got longer.
    @discardableResult
    public mutating func keep(
        _ range: ItemRange,
        transcripts: TranscriptIndex,
        snapping: SnapSettings = .default,
        byHand: Bool = false
    ) throws(EditError) -> TimeInterval {
        let transcript = try transcripts.transcript(containing: range)
        let time = try CutPointSnapper(transcript: transcript, settings: snapping).timeRange(for: range)
        let before = duration
        restore(time, from: transcript.source, byHand: byHand)
        return duration - before
    }

    /// Pauses longer than this are shortened when nothing else is asked: by `remove_silences` and the editor's
    /// Remove Silences.
    public static let defaultSilenceThreshold: TimeInterval = 0.7
    /// The pause left behind when nothing else is asked.
    public static let defaultSilenceAir: TimeInterval = 0.3
    /// The thresholds the editor's Remove Silences offers, in seconds: more than the air it leaves.
    public static let silenceThresholds: ClosedRange<TimeInterval> = 0.4...9.9

    /// A threshold as the editor's Remove Silences keeps it: a tenth of a second, within ``silenceThresholds``.
    public static func silenceThreshold(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return defaultSilenceThreshold }
        return min(silenceThresholds.upperBound, max(silenceThresholds.lowerBound, (seconds * 10).rounded() / 10))
    }

    /// Shortens every pause on the main track that's longer than `threshold`, leaving `air` seconds of it.
    ///
    /// The air left is split between the end of the word before and the start of the word after, in the
    /// same proportion as ``SnapSettings/trailPad`` to ``SnapSettings/leadPad``. It's a broad pass, so it
    /// leaves alone any pause where it would move an edge the creator placed by hand.
    ///
    /// - Parameter clips: Only these clips, and the pieces they're cut into, as the editor's command does
    ///   with clips selected. Nil is the whole main track.
    /// - Returns: How many pauses were shortened.
    @discardableResult
    public mutating func removeSilences(
        longerThan threshold: TimeInterval,
        leaving air: TimeInterval,
        transcripts: TranscriptIndex,
        snapping: SnapSettings = .default,
        in clips: Set<ClipID>? = nil
    ) throws(EditError) -> Int {
        guard air > 0, threshold > air else { throw .invalidSilenceSettings }
        let padTotal = snapping.leadPad + snapping.trailPad
        let airBefore = padTotal > 0 ? air * snapping.trailPad / padTotal : air / 2
        let airAfter = air - airBefore

        var shortened = 0
        var scope = clips
        for source in sourcesOnMainTrack {
            guard let transcript = transcripts[source] else { continue }
            for silence in transcript.silences where silence.duration > threshold {
                let region = TimeRange(start: silence.start + airBefore, end: silence.end - airAfter)
                let before = duration
                scope = remove(region, from: source, byHand: false, sparingHandPlacedEdges: true, within: scope)
                if duration < before - Self.sliver { shortened += 1 }
            }
        }
        return shortened
    }

    /// Sets a main-track clip's layout.
    public mutating func setLayout(_ layout: Layout, for clipID: ClipID) throws(EditError) {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        main[index].layout = layout
    }

    /// The items of a transcript that the main track plays: those whose middle falls inside one of its
    /// source's clips. Everything else has been cut, or was never added.
    public func usedItems(of transcript: Transcript) -> Set<TranscriptItemID> {
        let ranges = main.filter { $0.source == transcript.source }.map(\.playedRange)
        var used = Set<TranscriptItemID>()
        for item in transcript.items {
            let middle = (item.start + item.end) / 2
            if ranges.contains(where: { $0.start <= middle && middle < $0.end }) {
                used.insert(item.id)
            }
        }
        return used
    }

    // MARK: - Time primitives

    /// The sources the main track plays, in order of first appearance.
    var sourcesOnMainTrack: [SourceID] {
        var seen = Set<SourceID>()
        return main.map(\.source).filter { seen.insert($0).inserted }
    }

    /// Takes a stretch of one source's time out of every main-track clip that plays it, splitting clips
    /// where the stretch falls in their middle. It works on what each clip plays, nudges included.
    ///
    /// - Parameters:
    ///   - byHand: Marks the edges this makes as placed by hand.
    ///   - sparingHandPlacedEdges: For broad passes: does nothing if the stretch would move an edge placed
    ///     by hand.
    public mutating func remove(_ region: TimeRange, from source: SourceID, byHand: Bool = false, sparingHandPlacedEdges: Bool = false) {
        _ = remove(region, from: source, byHand: byHand, sparingHandPlacedEdges: sparingHandPlacedEdges, within: nil)
    }

    /// Removes a stretch of one source's time from the clips that play it, or only from the clips in `scope`
    /// when it's given.
    ///
    /// - Returns: The scope after the cut: a clip cut in two keeps both pieces in it, and a clip cut away
    ///   leaves it. Nil stays nil.
    private mutating func remove(_ region: TimeRange, from source: SourceID, byHand: Bool, sparingHandPlacedEdges: Bool,
                                 within scope: Set<ClipID>?) -> Set<ClipID>? {
        func inScope(_ clip: Clip) -> Bool { clip.source == source && (scope?.contains(clip.id) ?? true) }
        guard region.duration > Self.sliver else { return scope }
        if sparingHandPlacedEdges, main.contains(where: { inScope($0) && $0.wouldMoveHandPlacedEdge(removing: region) }) {
            return scope
        }
        var result: [Clip] = []
        var updated = scope
        for clip in main {
            guard inScope(clip), clip.playedRange.overlaps(region) else {
                result.append(clip)
                continue
            }
            updated?.remove(clip.id)
            let pieces = clip.playedRange.subtracting(region).filter { $0.duration > Self.sliver }
            for (offset, piece) in pieces.enumerated() {
                // The first piece keeps the clip's id; a second piece, after a cut in the middle, is a new clip.
                let copy = offset == 0 ? clip : clip.withID(makeClipID())
                updated?.insert(copy.id)
                result.append(copy.playing(piece, byHand: byHand))
            }
        }
        main = result
        return updated
    }

    /// Adds a stretch of one source's time back to the main track, skipping what's already there.
    public mutating func restore(_ region: TimeRange, from source: SourceID, byHand: Bool = false) {
        guard region.duration > Self.sliver else { return }
        var missing = [region]
        for clip in main where clip.source == source {
            missing = missing.flatMap { $0.subtracting(clip.playedRange) }
        }
        for piece in missing where piece.duration > Self.sliver {
            // A piece that meets a clip extends it, whether it meets what the clip plays or its snapped edge:
            // keeping the words past a nudged edge does away with that edge, but only if bridging the
            // nudge doesn't repeat audio another clip already plays.
            if let index = main.firstIndex(where: {
                $0.source == source && $0.endMeets(piece.start)
                    && !playsAny(of: TimeRange(start: $0.playedRange.end, end: piece.start), from: source)
            }) {
                let clip = main[index]
                main[index] = clip.playing(TimeRange(start: clip.playedRange.start, end: piece.end), byHand: byHand)
            } else if let index = main.firstIndex(where: {
                $0.source == source && $0.startMeets(piece.end)
                    && !playsAny(of: TimeRange(start: piece.end, end: $0.playedRange.start), from: source)
            }) {
                let clip = main[index]
                main[index] = clip.playing(TimeRange(start: piece.start, end: clip.playedRange.end), byHand: byHand)
            } else {
                insertClip(for: piece, from: source, byHand: byHand)
            }
        }
        joinTouchingClips()
    }

    /// Whether extending across a nudged gap would repeat any audio already on the main track.
    private func playsAny(of range: TimeRange, from source: SourceID) -> Bool {
        guard range.duration > Self.sliver else { return false }
        return main.contains { $0.source == source && $0.playedRange.overlaps(range) }
    }

    /// Inserts a new clip for a stretch of source time after the clip that plays that source just before it,
    /// or before the clip that plays it just after, or at the end.
    private mutating func insertClip(for piece: TimeRange, from source: SourceID, byHand: Bool) {
        let sameSource = main.indices.filter { main[$0].source == source }
        let template = sameSource.first.map { main[$0] }
        let clip = Clip(
            id: makeClipID(),
            source: source,
            sourceIn: piece.start,
            sourceOut: piece.end,
            startPlacedByHand: byHand,
            endPlacedByHand: byHand,
            audio: template?.audio,
            voiceLevel: template?.voiceLevel ?? 0,
            systemAudioLevel: template?.systemAudioLevel ?? 0,
            layout: template?.layout ?? .automatic,
            look: template?.look ?? ClipLook(),
            screenTransform: template?.screenTransform,
            cameraTransform: template?.cameraTransform
        )
        let earlier = sameSource.filter { main[$0].playedRange.end <= piece.start + Self.sliver }
        if let previous = earlier.max(by: { main[$0].playedRange.end < main[$1].playedRange.end }) {
            main.insert(clip, at: previous + 1)
        } else if let next = sameSource.filter({ main[$0].playedRange.start >= piece.end - Self.sliver })
            .min(by: { main[$0].playedRange.start < main[$1].playedRange.start })
        {
            main.insert(clip, at: next)
        } else {
            main.append(clip)
        }
    }

    /// Joins neighbouring main-track clips that play one continuous stretch of a source the same way.
    private mutating func joinTouchingClips() {
        var result: [Clip] = []
        for clip in main {
            // Clips from a split, and edges that have been nudged, stay as they are.
            if var last = result.last, last.hasSamePresentation(as: clip),
                abs(last.sourceOut - clip.sourceIn) < Self.sliver,
                !clip.startsAtSplit, last.endNudge == 0, clip.startNudge == 0
            {
                last.sourceOut = clip.sourceOut
                last.endNudge = clip.endNudge
                last.endPlacedByHand = clip.endPlacedByHand
                result[result.count - 1] = last
            } else {
                result.append(clip)
            }
        }
        main = result
    }
}

extension Clip {
    /// The clip narrowed or widened to play `range` of its source.
    ///
    /// An edge that doesn't move keeps its nudge, its split and whether it was placed by hand, so a cut
    /// elsewhere leaves a creator's fix alone. An edge that moves starts fresh: put where it now is, with no
    /// nudge, and placed by hand only if `byHand`. So does an edge whose place the new range no longer
    /// contains, so the range between the edges never runs backwards.
    func playing(_ range: TimeRange, byHand: Bool = false) -> Clip {
        var clip = self
        let played = playedRange
        let startStays = abs(range.start - played.start) < Edit.sliver
        if !startStays || sourceIn >= range.end - Edit.sliver {
            clip.sourceIn = range.start
            clip.startNudge = 0
        }
        if !startStays {
            clip.startsAtSplit = false
            clip.startPlacedByHand = byHand
        }
        let endStays = abs(range.end - played.end) < Edit.sliver
        if !endStays || sourceOut <= range.start + Edit.sliver {
            clip.sourceOut = range.end
            clip.endNudge = 0
        }
        if !endStays { clip.endPlacedByHand = byHand }
        return clip
    }

    /// Whether taking a stretch of its source out would move or remove an edge placed by hand.
    func wouldMoveHandPlacedEdge(removing region: TimeRange) -> Bool {
        let played = playedRange
        guard region.overlaps(played) else { return false }
        if startPlacedByHand, region.start <= played.start + Edit.sliver { return true }
        if endPlacedByHand, region.end >= played.end - Edit.sliver { return true }
        return false
    }

    /// Whether the clip ends at `time`, played or snapped.
    func endMeets(_ time: TimeInterval) -> Bool {
        abs(playedRange.end - time) < Edit.sliver || abs(sourceOut - time) < Edit.sliver
    }

    /// Whether the clip starts at `time`, played or snapped.
    func startMeets(_ time: TimeInterval) -> Bool {
        abs(playedRange.start - time) < Edit.sliver || abs(sourceIn - time) < Edit.sliver
    }

    /// The same clip under a new id.
    func withID(_ id: ClipID) -> Clip {
        Clip(
            id: id,
            source: source,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            startNudge: startNudge,
            endNudge: endNudge,
            startsAtSplit: startsAtSplit,
            startPlacedByHand: startPlacedByHand,
            endPlacedByHand: endPlacedByHand,
            audio: audio,
            isMuted: isMuted,
            voiceLevel: voiceLevel,
            systemAudioLevel: systemAudioLevel,
            speed: speed,
            layout: layout,
            look: look,
            screenTransform: screenTransform,
            cameraTransform: cameraTransform
        )
    }
}

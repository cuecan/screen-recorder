import Foundation

/// Holding the picture on one frame and speeding clips up: retiming, not effects (docs/decisions.md, 59).
extension Edit {
    /// Holds the picture over a stretch of the edited timeline while the camera and the voice play on.
    ///
    /// The hold is kept in source time, so it follows later cuts. A stretch that crosses a cut gives one freeze
    /// per clip, each holding the same frame where they share a source.
    ///
    /// - Parameter frameTime: The timeline time of the frame to hold. The stretch's start if nil.
    /// - Returns: The freezes made.
    @discardableResult
    public mutating func freeze(timeline range: TimeRange, holdingFrameAt frameTime: TimeInterval? = nil) throws(EditError) -> [Freeze] {
        guard range.end > range.start else { throw .invalidTimeRange(range) }
        let pieces = sourcePieces(of: range)
        guard !pieces.isEmpty else { throw .timeOutsideEdit(range.start, duration: duration) }
        let held = frameTime.flatMap { sourceTime(at: $0) }
        var made: [Freeze] = []
        for piece in pieces {
            let frame = held?.source == piece.source ? held?.time : made.first(where: { $0.source == piece.source })?.frame
            // A new hold replaces any old one it covers, so two never fight over the same moment.
            freezes.removeAll { $0.source == piece.source && piece.range.start <= $0.range.start + Self.sliver && $0.range.end <= piece.range.end + Self.sliver }
            let freeze = Freeze(id: makeFreezeID(), source: piece.source, range: piece.range, frame: frame ?? piece.range.start)
            freezes.append(freeze)
            made.append(freeze)
        }
        return made
    }

    /// Changes which stretch of its source a freeze covers, such as when its band is stretched.
    public mutating func setFreezeRange(_ id: FreezeID, to range: TimeRange) throws(EditError) {
        guard let index = freezes.firstIndex(where: { $0.id == id }) else { throw .unknownFreeze(id) }
        guard range.end > range.start else { throw .invalidTimeRange(range) }
        freezes[index].range = range
        freezes[index].frame = min(max(freezes[index].frame, range.start), range.end)
    }

    /// Takes a freeze out: the picture plays normally there again.
    public mutating func removeFreeze(_ id: FreezeID) throws(EditError) {
        guard freezes.contains(where: { $0.id == id }) else { throw .unknownFreeze(id) }
        freezes.removeAll { $0.id == id }
    }

    /// Takes out every freeze that holds anywhere in a stretch of the timeline.
    @discardableResult
    public mutating func removeFreezes(overlapping range: TimeRange) -> Int {
        let pieces = sourcePieces(of: range)
        let before = freezes.count
        freezes.removeAll { freeze in pieces.contains { $0.source == freeze.source && $0.range.overlaps(freeze.range) } }
        return before - freezes.count
    }

    /// The freeze holding a moment of a source, if any. A later freeze wins over an earlier one.
    public func freeze(holding time: TimeInterval, in source: SourceID) -> Freeze? {
        freezes.last { $0.source == source && $0.range.start <= time && time < $0.range.end }
    }

    /// Plays a clip at a speed: 1×, 1.5×, 2×, 4× or 8×, with its sound pitch-kept or muted.
    @discardableResult
    public mutating func setSpeed(_ speed: ClipSpeed, for clipID: ClipID) throws(EditError) -> Clip {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        main[index].speed = speed
        return main[index]
    }

    /// Mutes or unmutes a clip's sound: the voice and system audio.
    public mutating func setMuted(_ muted: Bool, for clipID: ClipID) throws(EditError) {
        guard let index = main.firstIndex(where: { $0.id == clipID }) else { throw .unknownClip(clipID) }
        main[index].isMuted = muted
    }
}

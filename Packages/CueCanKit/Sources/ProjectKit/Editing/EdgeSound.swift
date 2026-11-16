import Foundation

/// A clip edge that may catch a word: sound runs right across it (docs/decisions.md, 75). Claude can't hear,
/// so the tools measure each edge against the recording's own silence level instead.
///
/// The judgement is the silence detector's own (40): a frame is sound when it's at or above the detector's
/// threshold, and sound shorter than the detector's minimum, between quiet frames, doesn't count. An edge with
/// sound on both sides of it cuts through that sound. An edge with sound on one side only is where sound starts
/// or stops, which is a clean cut. So is an edge at the bottom of a dip between words or syllables, the same
/// dips the editor's blade snaps to (``SoundEnvelope/dip(in:near:depth:reach:)``, docs/decisions.md, 74), since
/// running speech has no quiet frame to cut at. Whether this catches what a listener hears as a clipped word is TEST
/// NEEDED, and the dip's 6 dB depth is AUTHOR'S TAKE NEEDED.
public struct EdgeSound: Sendable, Equatable {
    public var clip: ClipID
    public var edge: ClipEdge
    /// Where the edge is, in the source's time and on the edited timeline.
    public var sourceTime: TimeInterval
    public var timelineTime: TimeInterval
    /// How far the quieter of the two frames either side of the edge is over the silence threshold, in dB.
    public var overSilence: Double
    /// How long the sound runs before the edge, and after it, in the source's time, up to ``reach``.
    public var soundBefore: TimeInterval
    public var soundAfter: TimeInterval
    /// How far the nearest dip between words or syllables is, before and after the edge, within the sound, in
    /// the source's time: a smaller nudge than clearing the sound altogether.
    public var dipBefore: TimeInterval?
    public var dipAfter: TimeInterval?

    /// How far either side of an edge the sound is followed, in seconds. A limit on what's reported, not part
    /// of the judgement.
    public static let reach: TimeInterval = 2

    /// How far to move the edge outward to keep the sound whole, and inward to leave it out.
    public var toKeepIt: TimeInterval { edge == .start ? soundBefore : soundAfter }
    public var toLeaveItOut: TimeInterval { edge == .start ? soundAfter : soundBefore }

    /// Every clip edge in the edit that sound runs across, in timeline order. Edges at a join that rolls play
    /// straight on, so they're left out, as are muted clips and edges with no measured levels.
    public static func edges(in edit: Edit, levels: [SourceID: SourceLevels]) -> [EdgeSound] {
        var found: [EdgeSound] = []
        for placed in edit.placements {
            let clip = placed.clip
            guard !clip.isMuted, clip.speed.sound != .muted else { continue }
            // A clip playing another source's mic plays it at the same source times.
            guard let measured = levels[clip.audio?.source ?? clip.source] else { continue }
            let envelope = measured.envelope
            for edge in ClipEdge.allCases where !edit.isRollable(edge, of: clip.id) {
                let time = edge == .start ? clip.playedRange.start : clip.playedRange.end
                guard let sound = sound(across: time, in: envelope, threshold: measured.threshold, minimumSound: measured.minimumSound) else { continue }
                found.append(EdgeSound(clip: clip.id, edge: edge, sourceTime: time,
                                       timelineTime: edge == .start ? placed.timeline.start : placed.timeline.end,
                                       overSilence: sound.over, soundBefore: sound.before, soundAfter: sound.after,
                                       dipBefore: sound.dipBefore, dipAfter: sound.dipAfter))
            }
        }
        return found
    }

    /// The edges in `after` that sound runs across and that weren't already in `before` at the same source
    /// time: what a change made or moved.
    public static func new(in after: [EdgeSound], comparedTo before: [EdgeSound]) -> [EdgeSound] {
        let old = Set(before.map { "\($0.clip) \($0.edge) \(Int(($0.sourceTime * 1000).rounded()))" })
        return after.filter { !old.contains("\($0.clip) \($0.edge) \(Int(($0.sourceTime * 1000).rounded()))") }
    }

    /// The sound running across a source time: how far the quieter side is over the threshold, how long it
    /// runs either side, and the nearest dips in it. Nil when either side is quiet, or the time is at a dip.
    static func sound(across time: TimeInterval, in envelope: SoundEnvelope, threshold: Double, minimumSound: TimeInterval)
        -> (over: Double, before: TimeInterval, after: TimeInterval, dipBefore: TimeInterval?, dipAfter: TimeInterval?)?
    {
        let frameDuration = envelope.frameDuration
        let reachFrames = Int((reach / frameDuration).rounded(.up))
        let before = envelope.frame(at: time - frameDuration / 2)
        let after = envelope.frame(at: time + frameDuration / 2)
        guard before >= 0, after < envelope.levels.count, before < after else { return nil }
        // A window around the edge, marked as the detector marks it, with sound too short to count taken out.
        let first = max(0, before - reachFrames - 1), last = min(envelope.levels.count - 1, after + reachFrames + 1)
        var isSound = envelope.levels[first...last].map { $0 >= threshold }
        fillShortSound(&isSound, shorterThan: Int((minimumSound / frameDuration).rounded()))
        func sound(_ frame: Int) -> Bool { isSound[frame - first] }
        guard sound(before), sound(after) else { return nil }
        // Cut at the bottom of a dip: between words in running speech.
        if envelope.isDip(before) || envelope.isDip(after) { return nil }
        var start = before
        while start - 1 >= first, sound(start - 1), before - start < reachFrames { start -= 1 }
        var end = after
        while end + 1 <= last, sound(end + 1), end - after < reachFrames { end += 1 }
        let soundStart = envelope.start + Double(start) * frameDuration
        let soundEnd = envelope.start + Double(end + 1) * frameDuration
        let over = min(envelope.levels[before], envelope.levels[after]) - threshold
        let soundBefore = max(0, time - soundStart), soundAfter = max(0, soundEnd - time)
        let dipBefore = envelope.nearestDip(from: time, forward: false, within: soundBefore).map { time - $0 }
        let dipAfter = envelope.nearestDip(from: time, forward: true, within: soundAfter).map { $0 - time }
        return (over, soundBefore, soundAfter, dipBefore, dipAfter)
    }

    /// Sound shorter than `length` frames between quiet frames becomes quiet, as in the detector.
    static func fillShortSound(_ flags: inout [Bool], shorterThan length: Int) {
        guard length > 0 else { return }
        var index = 0
        while index < flags.count {
            guard flags[index] else { index += 1; continue }
            var end = index
            while end < flags.count, flags[end] { end += 1 }
            if index > 0, end < flags.count, end - index < length {
                for frame in index..<end { flags[frame] = false }
            }
            index = end
        }
    }
}

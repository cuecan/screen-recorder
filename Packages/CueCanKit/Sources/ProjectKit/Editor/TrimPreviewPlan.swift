import Foundation

/// The two output frames meeting at a proposed trim. It applies the same edge operation as the edit,
/// in memory only, so ripple and rolling joins, speed and recording limits agree with the committed cut.
public struct TrimPreviewPlan: Sendable {
    public struct Frame: Equatable, Sendable {
        public let clip: ClipID
        public let time: TimeInterval
    }

    public let edit: Edit
    public let cut: TimeInterval
    public let outgoing: Frame?
    public let incoming: Frame?
    public let deltaFrames: Int
    public let atLimit: Bool
    public let edge: ClipEdge

    public init(edit original: Edit, clip id: ClipID, edge: ClipEdge, sourceTime: TimeInterval,
                sourceDuration: TimeInterval?, frameDuration: TimeInterval, rolling: Bool = true) throws {
        guard let clip = original.main.first(where: { $0.id == id }) else { throw EditError.unknownClip(id) }
        guard sourceTime.isFinite else { throw EditError.edgeOutsideRecording(id) }
        let rate = (1 / frameDuration).rounded()
        guard frameDuration.isFinite, frameDuration > 0, rate.isFinite, rate >= 1, rate < Double(Int.max) else {
            throw EditError.invalidTimeRange(TimeRange(start: 0, end: frameDuration))
        }
        let clock = Timecode(frameRate: Int(rate))
        var candidate = original
        let changed = try candidate.setEdge(edge, of: id, to: sourceTime, sourceDuration: sourceDuration, rolling: rolling)
        let time = edge == .start ? changed.playedRange.start : changed.playedRange.end
        let start = edge == .start ? clip.playedRange.start : clip.playedRange.end
        let delta = ((time - start) / clip.speed.rate * Double(clock.frameRate)).rounded()
        guard delta.isFinite, delta >= Double(Int.min), delta < Double(Int.max) else { throw EditError.edgeOutsideRecording(id) }
        deltaFrames = Int(delta)
        self.edge = edge
        if let bounds = original.edgeRange(edge, of: id, sourceDuration: sourceDuration, rolling: rolling) {
            atLimit = abs(time - bounds.lowerBound) < 1e-8 || abs(time - bounds.upperBound) < 1e-8
        } else { atLimit = false }
        edit = candidate
        let placements = candidate.placements
        guard let index = placements.firstIndex(where: { $0.clip.id == id }) else { throw EditError.unknownClip(id) }
        cut = edge == .start ? placements[index].timeline.start : placements[index].timeline.end
        let before = clock.frameTime(before: cut)
        let after = clock.frameTime(atOrAfter: cut)
        let outIndex = edge == .start ? index - 1 : index
        let inIndex = edge == .start ? index : index + 1
        func frame(_ index: Int, at time: TimeInterval) -> Frame? {
            guard placements.indices.contains(index) else { return nil }
            let placed = placements[index]
            guard time >= placed.timeline.start - 1e-9, time < placed.timeline.end - 1e-9 else { return nil }
            return Frame(clip: placed.clip.id, time: time)
        }
        outgoing = cut > 0 ? frame(outIndex, at: before) : nil
        incoming = frame(inIndex, at: after)
    }
}

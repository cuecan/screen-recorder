import Foundation
import ProjectKit

/// A transient trim target. Its edit is the pre-gesture snapshot, never an edit written by the loupe.
struct TrimLoupeRequest: Identifiable {
    let id = UUID()
    let edit: Edit
    let clip: ClipID
    let edge: ClipEdge
    let sourceTime: TimeInterval
    let sourceDuration: TimeInterval?
    let frameDuration: TimeInterval
    /// Whether the edge takes a rolling join's neighbour with it, as the edit it previews will.
    var rolling = false

    struct Key: Hashable {
        let revision: Int
        let clip: ClipID
        let edge: ClipEdge
        let time: TimeInterval
    }
    var key: Key { Key(revision: edit.revision, clip: clip, edge: edge, time: sourceTime) }
    var base: Key { Key(revision: edit.revision, clip: clip, edge: edge, time: 0) }
    func plan() throws -> TrimPreviewPlan {
        try TrimPreviewPlan(edit: edit, clip: clip, edge: edge, sourceTime: sourceTime,
                            sourceDuration: sourceDuration, frameDuration: frameDuration, rolling: rolling)
    }
}

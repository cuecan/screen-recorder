import Foundation
import ProjectKit

/// Converts a moment in one source's time into another's, through their sync offsets.
///
/// A source synced to a reference plays its time `t` at `t + offset` in the reference
/// (``SourceSync``). Sources are followed up to the one that has no reference, so a mic synced to a second
/// angle, synced in turn to the main camera, still lines up.
public struct SourceClock: Sendable {
    private let sync: [SourceID: SourceSync]

    public init(project: Project) {
        sync = Dictionary(uniqueKeysWithValues: project.sources.compactMap { source in source.sync.map { (source.id, $0) } })
    }

    /// The source a source is ultimately lined up with, and the time `t` is there.
    func root(of source: SourceID, at time: TimeInterval) -> (source: SourceID, time: TimeInterval) {
        var current = source
        var time = time
        var visited: Set<SourceID> = [source]
        while let link = sync[current], visited.insert(link.reference).inserted {
            time += link.offset
            current = link.reference
        }
        return (current, time)
    }

    /// The time in `target` of the moment at `time` in `source`, or nil if the two aren't lined up with
    /// each other.
    public func time(_ time: TimeInterval, in source: SourceID, as target: SourceID) -> TimeInterval? {
        if source == target { return time }
        let from = root(of: source, at: time)
        let zero = root(of: target, at: 0)
        guard from.source == zero.source else { return nil }
        return from.time - zero.time
    }
}

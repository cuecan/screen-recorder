import Foundation

/// The timeline's ordinary, Shift-range and Command-toggle clip selection. The anchor is ephemeral UI
/// intent, not an edit and not part of the agent's persisted selection.
public struct ClipPicking: Sendable {
    public enum Mode: Equatable, Sendable { case replace, extend, toggle }
    public private(set) var anchor: ClipID?
    public init() {}

    public mutating func clear() { anchor = nil }

    /// Picks only existing clips, in their timeline order. If an agent removed the anchor, the first
    /// remaining selected clip becomes the range anchor; an empty selection starts at the clicked clip.
    public mutating func pick(_ id: ClipID, mode: Mode, selected: Set<ClipID>, ordered: [ClipID]) -> Set<ClipID> {
        guard let index = ordered.firstIndex(of: id) else { return selected.intersection(ordered) }
        let existing = selected.intersection(ordered)
        switch mode {
        case .replace:
            anchor = id
            return [id]
        case .extend:
            let start = anchor.flatMap { existing.contains($0) ? ordered.firstIndex(of: $0) : nil }
                ?? ordered.firstIndex(where: { existing.contains($0) }) ?? index
            anchor = ordered[start]
            return Set(ordered[min(start, index)...max(start, index)])
        case .toggle:
            var result = existing
            if result.contains(id) {
                result.remove(id)
                if anchor == id || anchor.map({ !ordered.contains($0) }) == true {
                    anchor = ordered.first(where: { result.contains($0) })
                }
            } else {
                result.insert(id)
                anchor = id
            }
            return result
        }
    }
}

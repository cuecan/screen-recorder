import Foundation

/// The editor selects one kind of thing at a time. A selected edge always belongs to its selected clip.
/// The persisted `EditorState.Selection` keeps its existing JSON shape for MCP clients.
public enum EditorSelection: Equatable, Sendable {
    case none
    case clips(Set<ClipID>)
    case clipEdge(clip: ClipID, edge: ClipEdge)
    case overlays(Set<ClipID>)
    case freeze(FreezeID)
    case words(ItemRange)

    public var clipIDs: Set<ClipID> {
        switch self {
        case .clips(let ids): ids
        case .clipEdge(let clip, _): [clip]
        default: []
        }
    }
    public var overlayIDs: Set<ClipID> { if case .overlays(let ids) = self { ids } else { [] } }
    public var freezeID: FreezeID? { if case .freeze(let id) = self { id } else { nil } }
    public var wordRange: ItemRange? { if case .words(let range) = self { range } else { nil } }
    public var edge: (clip: ClipID, edge: ClipEdge)? {
        if case .clipEdge(let clip, let edge) = self { (clip, edge) } else { nil }
    }
    public var isEmpty: Bool { clipIDs.isEmpty && overlayIDs.isEmpty && freezeID == nil && wordRange == nil }

    /// Drops objects removed by an edit without changing the kind of the remaining selection.
    public func retaining(in edit: Edit) -> Self {
        switch self {
        case .none, .words: self
        case .clips(let ids): .clips(ids.intersection(edit.main.map(\.id)))
        case .clipEdge(let clip, _): edit.main.contains { $0.id == clip } ? self : .none
        case .overlays(let ids): .overlays(ids.intersection(edit.overlays.map(\.id)))
        case .freeze(let id): edit.freezes.contains { $0.id == id } ? self : .none
        }
    }

    public var persisted: EditorState.Selection {
        .init(clips: clipIDs.sorted(), overlays: overlayIDs.sorted(), freezes: freezeID.map { [$0] } ?? [], words: wordRange)
    }
}

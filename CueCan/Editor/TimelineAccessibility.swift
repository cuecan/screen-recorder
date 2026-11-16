import ProjectKit
import SwiftUI

/// Nonvisual controls for the timeline's Canvas. Each clip, edge, overlay and hold can be reached with
/// assistive technology, using the same selections and operations as the pointer tools. Words are reached in
/// the transcript, where they're picked and fixed (docs/decisions.md, 74).
struct TimelineAccessibility: View {
    let model: EditorModel
    let viewport: TimelineViewport

    var body: some View {
        if let edit = model.edit, let timeline = model.timeline {
            ZStack(alignment: .topLeading) {
                ForEach(timeline.clips, id: \.clip.id) { placed in
                    if let rect = rect(placed.timeline, lane: .video) {
                        Button {
                            model.selectClip(placed.clip.id)
                        } label: { Color.clear }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clip \(placed.index + 1), \(model.clock(placed.timeline.start)) to \(model.clock(placed.timeline.end))")
                        .accessibilityValue(placed.clip.look.captions ? "Captions on" : "")
                        .accessibilityAddTraits(model.selection.clipIDs.contains(placed.clip.id) ? .isSelected : [])
                        .accessibilityActions {
                            Button("Add to selection") {
                                model.selection = .clips(model.selection.clipIDs.union([placed.clip.id]))
                            }
                            Button("Select start edge") { model.selection = .clipEdge(clip: placed.clip.id, edge: .start) }
                            Button("Select end edge") { model.selection = .clipEdge(clip: placed.clip.id, edge: .end) }
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
                ForEach(edit.overlays, id: \.id) { overlay in
                    if let rect = timeline.overlays.filter({ $0.overlay.id == overlay.id }).compactMap({ rect($0.timeline, lane: .overlays) }).first {
                        Button { model.selection = .overlays([overlay.id]) } label: { Color.clear }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Overlay, \(model.displayName(of: overlay))")
                            .accessibilityAddTraits(model.selection.overlayIDs.contains(overlay.id) ? .isSelected : [])
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                ForEach(edit.freezes, id: \.id) { hold in
                    if let rect = edit.timelinePieces(of: hold.range, in: hold.source).compactMap({ rect($0.timeline, lane: .video) }).first {
                        Button {
                            model.selection = .freeze(hold.id)
                        } label: { Color.clear }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hold, source time \(model.clock(hold.range.start)) to \(model.clock(hold.range.end))")
                        .frame(width: rect.width, height: 14)
                        .position(x: rect.midX, y: rect.maxY - 7)
                    }
                }
            }
            .frame(width: viewport.width, height: TimelineView.height)
        }
    }

    /// Synthetic accessibility children occupy their actual visible lane, rather than a tall invisible
    /// stack whose controls fall outside the timeline once an edit has many clips.
    private func rect(_ range: TimeRange, lane: TimelineLane) -> CGRect? {
        let start = TimelineLane.leading + range.start * model.zoom - viewport.offset
        let end = TimelineLane.leading + range.end * model.zoom - viewport.offset
        guard end >= 0, start <= viewport.width else { return nil }
        let left = max(0, start), right = min(viewport.width, end)
        return CGRect(x: left, y: lane.top + 4, width: max(1, right - left), height: lane.height - 8)
    }
}

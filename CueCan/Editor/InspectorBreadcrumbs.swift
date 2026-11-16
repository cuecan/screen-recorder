import ProjectKit
import SwiftUI

/// Where the inspector is, from the project down to what's selected: "Project › Clip 2 › Words". Every
/// level above the last goes back to it, and Project clears the selection, where the Look lives.
struct InspectorBreadcrumbs: View {
    let model: EditorModel

    struct Crumb {
        let title: String
        /// What clicking it selects.
        let selection: EditorSelection
    }

    var body: some View {
        let crumbs = Self.crumbs(for: model.selection, in: model)
        HStack(spacing: 5) {
            ForEach(crumbs.indices, id: \.self) { index in
                let crumb = crumbs[index]
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if index == crumbs.count - 1 {
                    Text(crumb.title)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button(crumb.title) { model.selection = crumb.selection }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .help(crumb.selection.isEmpty ? "Back to the project (Esc)" : "Back to \(crumb.title)")
                }
            }
            if !model.selectedClips.isEmpty {
                Spacer(minLength: 6)
                Text(model.clock(model.selectedClips.reduce(0) { $0 + $1.duration }))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Selection duration")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector location")
    }

    static func crumbs(for selection: EditorSelection, in model: EditorModel) -> [Crumb] {
        var crumbs = [Crumb(title: "Project", selection: .none)]
        guard let edit = model.edit else { return crumbs }
        func clip(_ id: ClipID) -> Crumb {
            Crumb(title: edit.position(of: id).map { "Clip \($0)" } ?? "Clip", selection: .clips([id]))
        }
        switch selection {
        case .none:
            break
        case .clips(let ids):
            if ids.count == 1, let id = ids.first {
                crumbs.append(clip(id))
            } else {
                crumbs.append(Crumb(title: "\(ids.count) clips", selection: selection))
            }
        case .clipEdge(let id, let edge):
            crumbs.append(clip(id))
            crumbs.append(Crumb(title: edge == .start ? "Start edge" : "End edge", selection: selection))
        case .words(let range):
            if let start = model.timelineRange(of: range)?.start, let placed = edit.placement(at: start) {
                crumbs.append(clip(placed.clip.id))
            }
            crumbs.append(Crumb(title: "Words", selection: selection))
        case .freeze(let id):
            if let freeze = edit.freezes.first(where: { $0.id == id }), let holder = edit.clip(holding: freeze) {
                crumbs.append(clip(holder.id))
            }
            crumbs.append(Crumb(title: "Hold", selection: selection))
        case .overlays(let ids):
            let single = ids.count == 1 ? ids.first.flatMap { id in edit.overlays.first { $0.id == id } } : nil
            crumbs.append(Crumb(title: single.map { "Overlay · \(model.displayName(of: $0))" } ?? "\(ids.count) overlays", selection: selection))
        }
        return crumbs
    }
}

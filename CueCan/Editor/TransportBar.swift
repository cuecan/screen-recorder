import ProjectKit
import SwiftUI

/// The Select, Blade and Trim tools in one group, and Snapping with the timeline's actions menu in a second
/// beside it, with every button the same size. Its own buttons, not a segmented picker, so pressing the
/// blade again while it's on keeps it on, which a picker doesn't report.
struct ToolStrip: View {
    let model: EditorModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            tools
            // Between the tools and Snapping.
            AudioTools(model: model, width: Self.width, height: Self.height)
            switches
        }
    }

    /// Select, Blade and Trim: one is always chosen, and it has the chip.
    private var tools: some View {
        HStack(spacing: 2) {
            button("Select", "cursorarrow", isOn: model.tool == .select, help: "Select (A)") { model.tool = .select }
            button("Blade", "scissors", isOn: model.tool == .blade,
                   help: model.keepsBlade ? "Blade (B), kept on. Click again for one cut at a time."
                                          : "Blade (B). Click again to keep it on.") { model.pickBlade() }
                .overlay(alignment: .bottomTrailing) {
                    if model.keepsBlade {
                        Image(systemName: "lock.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.accentColor)
                            .padding(2).accessibilityHidden(true)
                    }
                }
                .accessibilityValue(model.tool == .blade ? (model.keepsBlade ? "Kept on" : "One cut") : "")
            button("Trim", "arrow.left.and.right", isOn: model.tool == .trim,
                   help: "Trim (T): drag a clip to trim its nearer edge") { model.tool = .trim }
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }

    /// Snapping and the timeline's actions: neither is a tool, so they're a group of their own, with no chip.
    private var switches: some View {
        HStack(spacing: 2) {
            // A switch, not one of the tools: its icon is the accent colour while on and faint while off, with no
            // chip, so the chip always and only marks the tool.
            Button { model.snapping.toggle() } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: Self.width, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.snapping ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            .accessibilityLabel("Snapping")
            .accessibilityValue(model.snapping ? "On" : "Off")
            .accessibilityAddTraits(model.snapping ? .isSelected : [])
            .help("Snapping (N), \(model.snapping ? "on" : "off"): cuts stick to dips in the sound and to edit points.")
            Menu {
                TimelineActions(model: model)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: Self.width, height: Self.height)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Timeline actions")
            .help("Timeline actions")
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }

    private static let width: CGFloat = 32
    private static let height: CGFloat = 20

    private func button(_ title: String, _ symbol: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: Self.width, height: Self.height)
                .background {
                    // The chosen tool's chip is lighter than the strip in both appearances.
                    if isOn {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.white)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.14), radius: 0.75, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? .primary : .secondary)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(help)
    }
}

/// Under the previews (docs/ui.md, E1): the Select and Blade tools, Snapping, back, play and forward, the
/// time, and the timeline's zoom.
struct TransportBar: View {
    let model: EditorModel

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            ToolStrip(model: model)
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button("Previous edit", systemImage: "backward.end.fill") { model.jumpToEdit(forward: false) }
                    .help("Previous edit (↑)")
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") { model.togglePlayback() }
                    .font(.title2)
                    .help("Play or pause (Space)")
                Button("Next edit", systemImage: "forward.end.fill") { model.jumpToEdit(forward: true) }
                    .help("Next edit (↓)")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            EditorTimecode(model: model)
            Spacer(minLength: 0)
            Button("Zoom out", systemImage: "minus.magnifyingglass") { model.zoom = TimelineZoom.clamped(model.zoom / 1.5) }
                .labelStyle(.iconOnly).buttonStyle(.plain)
            ViewThatFits(in: .horizontal) {
                Slider(value: $model.zoomExponent, in: TimelineZoom.exponentRange)
                    .frame(width: 80)
                    .labelsHidden()
                    .accessibilityLabel("Timeline zoom")
                // EmptyView contributes no candidate for ViewThatFits to choose.
                Color.clear.frame(width: 0, height: 0)
            }
            .layoutPriority(-1)
            Button("Zoom in", systemImage: "plus.magnifyingglass") { model.zoom = TimelineZoom.clamped(model.zoom * 1.5) }
                .labelStyle(.iconOnly).buttonStyle(.plain)
            Button("Fit timeline", systemImage: "arrow.right.and.line.vertical.and.arrow.left") { model.fitRequest += 1 }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .help("Fit timeline (⇧Z)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .disabled(model.timeline == nil)
    }
}

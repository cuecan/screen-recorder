import ProjectKit
import SwiftUI

/// Moving feedback above the static timeline. Only this small canvas depends on the playback clock.
struct TimelineGuides: View {
    let model: EditorModel
    let viewport: TimelineViewport
    let hover: CGPoint?
    let drag: TimelineInteraction.DragState?

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: -viewport.offset, y: 0)
            drawBlade(&context, height: size.height)
            drawTrim(&context, height: size.height)
            drawLevel(&context)
            let playhead = x(model.currentTime)
            context.fill(Path(CGRect(x: playhead - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.red))
            context.fill(Path { path in
                path.move(to: CGPoint(x: playhead - 6, y: 0))
                path.addLine(to: CGPoint(x: playhead + 6, y: 0))
                path.addLine(to: CGPoint(x: playhead, y: 8))
                path.closeSubpath()
            }, with: .color(.red))
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Playhead")
        .accessibilityValue(model.clock(model.currentTime))
    }

    private func x(_ time: TimeInterval) -> Double { TimelineLane.leading + time * model.zoom }

    private func drawBlade(_ context: inout GraphicsContext, height: Double) {
        guard model.tool == .blade, let hover, hover.y >= TimelineLane.ruler else { return }
        guard let edit = model.edit, let timeline = model.timeline else { return }
        let hitContext = TimelineInteraction.Context(edit: edit, timeline: timeline,
                                                     zoom: model.zoom, snapping: model.snapping, selection: model.selection,
                                                     tool: model.tool, playhead: model.currentTime, snapper: model.snapper,
                                                     frameDuration: model.frameDuration)
        guard case .clip = TimelineInteraction().hit(hover, in: hitContext) else { return }
        if let drag, case .click = drag {} else if drag != nil { return }
        let time = max(0, (hover.x - TimelineLane.leading) / model.zoom)
        let (snapped, target) = model.snapped(time, tolerance: 8 / model.zoom)
        line(&context, at: x(snapped), height: height, dashed: true)
        let note = switch target {
        case .silenceEdge: "Silence edge"
        case .quietPoint: "Quiet point"
        case .screenStill: "Screen still"
        case .clipEdge: "Clip edge"
        case .playhead: "Playhead"
        case nil: ""
        }
        chip(&context, text: note.isEmpty ? model.clock(snapped) : "\(note) · \(model.clock(snapped))", at: x(snapped))
    }

    private func drawTrim(_ context: inout GraphicsContext, height: Double) {
        guard case .edge(let id, let edge, _, let start, let rate, _, let current, let snapped, _) = drag,
              abs(current - start) > 0.001,
              let placed = model.timeline?.clips.first(where: { $0.clip.id == id }) else { return }
        let time = placed.timelineTime(ofSourceTime: current)
        let frames = Int(((current - start) / rate / model.frameDuration).rounded())
        let name = edge == .start ? "Start" : "End"
        line(&context, at: x(time), height: height, dashed: !snapped)
        chip(&context, text: "\(name) \(frames >= 0 ? "+" : "−")\(abs(frames)) \(abs(frames) == 1 ? "frame" : "frames")", at: x(time))
    }

    /// While a clip's level line is dragged, its level over the clip.
    private func drawLevel(_ context: inout GraphicsContext) {
        guard case .level(let id, _, let current) = drag,
              let placed = model.timeline?.clips.first(where: { $0.clip.id == id }) else { return }
        let label = context.resolve(Text(SoundLevel.label(current)).font(.caption2.weight(.medium).monospacedDigit()).foregroundStyle(.white))
        let size = label.measure(in: CGSize(width: 200, height: 20))
        let width = size.width + 14, height = size.height + 4
        // Over the middle of the clip's visible part, just above the line.
        let left = max(x(placed.timeline.start), viewport.offset), right = min(x(placed.timeline.end), viewport.offset + viewport.width)
        let middle = min(max((left + right) / 2, viewport.offset + width / 2 + 4), viewport.offset + viewport.width - width / 2 - 4)
        let rect = CGRect(x: middle - width / 2, y: AudioLane.lineY(for: current) - height - 4, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.black.opacity(0.85)))
        context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func line(_ context: inout GraphicsContext, at x: Double, height: Double, dashed: Bool) {
        let path = Path { path in
            path.move(to: CGPoint(x: x, y: TimelineLane.ruler))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        context.stroke(path, with: .color(.yellow), style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 3] : []))
    }

    private func chip(_ context: inout GraphicsContext, text: String, at x: Double) {
        let label = context.resolve(Text(text).font(.caption2.weight(.medium)).foregroundStyle(.black))
        let textSize = label.measure(in: CGSize(width: 400, height: 20))
        let width = min(textSize.width + 12, viewport.width - 8)
        let left = min(max(viewport.offset + 4, x + 8), viewport.offset + viewport.width - width - 4)
        let rect = CGRect(x: left, y: TimelineLane.ruler + 2, width: width, height: textSize.height + 6)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(.yellow))
        context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

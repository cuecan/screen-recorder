import AppKit
import ProjectKit
import RenderKit
import SwiftUI
import UniformTypeIdentifiers

/// The timeline (docs/ui.md, E1): a ruler with dots where the screen went still, then three fixed lanes,
/// overlays, video and audio, with the words written in the audio lane once zoomed in (docs/decisions.md, 74).
/// Every gesture here is one of the edit's operations (E2).
struct TimelineView: View {
    let model: EditorModel

    static let labelWidth = 78.0
    static let leading = TimelineLane.leading
    static let ruler = TimelineLane.ruler
    static let lanes = TimelineLane.allCases
    static var height: Double { ruler + lanes.map(\.height).reduce(0, +) + 6 }

    @State private var interaction = TimelineInteraction()
    private var drag: DragState? { interaction.drag }
    @State private var hover: CGPoint?
    @State private var viewport = TimelineViewport(width: 800)
    @State private var position = ScrollPosition(x: 0)
    @State private var dragOrigin: CGPoint?
    @State private var trimLoupe = TrimLoupeModel()

    typealias DragState = TimelineInteraction.DragState
    typealias Hit = TimelineInteraction.Hit

    var body: some View {
        HStack(spacing: 0) {
            laneLabels
            Divider()
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    Color.clear
                        .frame(width: contentWidth(viewport: geometry.size.width), height: Self.height)
                        .overlay(alignment: .leading) {
                            canvas
                                .frame(width: geometry.size.width, height: Self.height)
                                .offset(x: viewport.offset)
                        }
                }
                .scrollPosition($position)
                .scrollIndicators(.visible)
                .onScrollGeometryChange(for: TimelineViewport.self) { geometry in
                    TimelineViewport(offset: geometry.contentOffset.x, width: geometry.containerSize.width)
                } action: { _, visible in viewport = visible }
                .onChange(of: model.fitRequest) { fit(width: geometry.size.width) }
                .onChange(of: model.duration) { old, new in if old == 0, new > 0 { fit(width: geometry.size.width) } }
                .modifier(TimelineNavigation(model: model, viewport: viewport, dragging: dragOrigin != nil, position: $position))
            }
        }
        .frame(height: Self.height)
        .background(.background)
        .overlay(alignment: .topLeading) {
            if trimLoupe.visible, let plan = trimLoupe.plan {
                let width = min(300, max(220, viewport.width - 16))
                let anchor = Self.labelWidth + 1 + Self.leading + plan.cut * model.zoom - viewport.offset
                TrimLoupeView(preview: trimLoupe, frameDuration: model.frameDuration)
                    .frame(width: width)
                    .offset(x: min(max(8, anchor - width / 2), Self.labelWidth + viewport.width - width - 8), y: -196)
            }
        }
        .zIndex(trimLoupe.visible ? 1 : 0)
        .onChange(of: drag) {
            if case .edge(let id, let edge, _, let start, _, _, let current, _, let rolls) = drag,
               abs(current - start) > 0.001, let edit = model.edit {
                trimLoupe.show(TrimLoupeRequest(edit: edit, clip: id, edge: edge, sourceTime: current,
                                               sourceDuration: model.sourceDuration(of: id), frameDuration: model.frameDuration, rolling: rolls), folder: model.folder)
            } else { trimLoupe.end() }
        }
        .onChange(of: model.keyboardTrimFeedback?.id) {
            if let request = model.keyboardTrimFeedback { trimLoupe.show(request, folder: model.folder, briefly: true) }
        }
        .onChange(of: model.selection) {
            if model.selection.edge == nil { trimLoupe.end() }
        }
        .onDisappear { trimLoupe.end() }
    }

    private var laneLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Self.ruler)
            ForEach(Self.lanes, id: \.name) { lane in
                Group {
                    if lane == .audio {
                        AudioLaneHeader(model: model)
                    } else {
                        Text(lane.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 10)
                .frame(height: lane.height)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .frame(width: Self.labelWidth)
    }

    private func contentWidth(viewport: Double) -> Double {
        max(viewport, model.duration * model.zoom + TimelineZoom.horizontalPadding)
    }

    private func fit(width: Double) {
        guard model.duration > 0 else { return }
        model.zoom = TimelineZoom.fitted(duration: model.duration, viewport: width)
        position.scrollTo(x: 0)
    }

    // MARK: - Geometry

    private func time(_ x: Double) -> TimeInterval { max(0, (x - Self.leading) / model.zoom) }

    private func contentPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + viewport.offset, y: point.y) }

    private var canvas: some View {
        ZStack {
            TimelineDrawing(model: model, drag: drag, viewport: viewport)
            TimelineGuides(model: model, viewport: viewport, hover: hover, drag: drag)
        }
        .contentShape(Rectangle())
        // Over a clip's level line, the pointer says it moves up and down.
        .pointerStyle(isOverLevelLine ? .rowResize : nil)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(dragChanged)
                .onEnded(dragEnded)
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hover = contentPoint(point)
            case .ended: hover = nil
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers, location in
            dropFiles(providers, at: contentPoint(location))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(model.edit?.main.count ?? 0) clips")
        .accessibilityChildren { TimelineAccessibility(model: model, viewport: viewport) }
    }

    private var isOverLevelLine: Bool {
        guard let hover, let context = interactionContext else { return false }
        if case .level = drag { return true }
        if case .voiceLevel = interaction.hit(hover, in: context) { return true }
        return false
    }

    // MARK: - Gestures

    private var interactionContext: TimelineInteraction.Context? {
        guard let edit = model.edit, let timeline = model.timeline else { return nil }
        return .init(edit: edit, timeline: timeline, zoom: model.zoom,
                     snapping: model.snapping, selection: model.selection, tool: model.tool,
                     playhead: model.currentTime, snapper: model.snapper, frameDuration: model.frameDuration,
                     sourceDurations: Dictionary(uniqueKeysWithValues: model.project?.sources.map { ($0.id, $0.duration) } ?? []))
    }

    private func dragChanged(_ value: DragGesture.Value) {
        guard let context = interactionContext else { return }
        if dragOrigin == nil { dragOrigin = contentPoint(value.startLocation) }
        guard let origin = dragOrigin else { return }
        if let time = interaction.changed(from: origin, to: contentPoint(value.location), in: context) {
            if model.isPlaying { model.pause() }
            model.seek(to: time)
        } else if model.isPlaying, abs(contentPoint(value.location).x - origin.x) > 3 {
            switch drag {
            case .edge, .overlay, .freeze: model.pause()
            default: break
            }
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        defer { dragOrigin = nil }
        guard let context = interactionContext, let origin = dragOrigin else { interaction = TimelineInteraction(); return }
        let point = contentPoint(value.location)
        let flags = NSEvent.modifierFlags
        let picking: ClipPicking.Mode = flags.contains(.command) ? .toggle : flags.contains(.shift) ? .extend : .replace
        // Mouse-up can carry a newer location than the last drag event. Commit that final target too.
        if let time = interaction.changed(from: origin, to: point, in: context) { model.seek(to: time) }
        for action in interaction.ended(from: origin, to: point, in: context) {
            switch action {
            case .trim(let clip, let edge, let time, let rolling): model.setEdge(edge, of: clip, toSourceTime: time, rolling: rolling)
            case .moveOverlay(let id, let range): model.moveOverlay(id, to: range)
            case .stretchFreeze(let id, let range): model.setFreezeRange(id, to: range)
            case .setVoiceLevel(let id, let level): model.setSound(ClipSoundChange(voiceLevel: level), for: [id])
            case .select(let selection): model.selection = selection
            case .click(let target): click(target, at: point, picking: picking)
            }
        }
    }

    private func click(_ target: Hit, at point: CGPoint, picking: ClipPicking.Mode) {
        if model.tool == .blade, case .clip = target {
            if model.isPlaying { model.pause() }
            model.blade(at: model.snapped(time(point.x), tolerance: 8 / model.zoom).time)
            model.bladeDidCut()
            return
        }
        switch target {
        case .clip(let id, _), .voiceLevel(let id):
            model.selectClip(id, mode: picking)
        case .overlay(let id, _):
            model.selection = .overlays([id])
        case .freeze(let id, _):
            model.selection = .freeze(id)
        case .ruler, .empty:
            model.seek(to: time(point.x))
        }
    }

    private func dropFiles(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        let at = time(location.x)
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.addOverlay(url, at: at) }
            }
        }
        return !providers.isEmpty
    }
}

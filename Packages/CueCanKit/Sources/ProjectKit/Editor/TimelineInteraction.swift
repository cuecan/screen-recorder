import Foundation

/// The editor's pointer tools, shared by views and interaction tests.
public enum TimelineTool: String, CaseIterable, Sendable { case select, blade, trim }

/// Fixed timeline lanes. Drawing and hit testing use the same dimensions.
public enum TimelineLane: Int, CaseIterable, Sendable {
    case overlays, video, audio
    public static let ruler = 24.0
    public static let leading = 10.0
    public var name: String { switch self { case .overlays: "Overlays"; case .video: "Video"; case .audio: "Audio" } }
    /// The audio lane holds the words, zoomed in, under the voice's waveform (docs/decisions.md, 74).
    public var height: Double { switch self { case .overlays: 40; case .video: 60; case .audio: 76 } }
    public var top: Double { Self.ruler + Self.allCases.prefix(rawValue).map(\.height).reduce(0, +) }
    public static func at(y: Double) -> Self? { allCases.first { $0.top <= y && y < $0.top + $0.height } }
}

/// Pure pointer interaction: idle → active → idle, or active → cancelled → idle if the edit changes.
/// The view applies emitted actions and handles platform modifiers and double-click timing.
public struct TimelineInteraction: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case active(revision: Int, drag: DragState)
        case cancelled
    }
    public enum Action: Equatable, Sendable {
        /// A clip's edge put at a source time. `rolling` when the Trim tool moved a join, so the neighbour's
        /// edge goes with it; otherwise only this clip changes.
        case trim(ClipID, ClipEdge, TimeInterval, rolling: Bool)
        case moveOverlay(ClipID, TimeRange)
        case stretchFreeze(FreezeID, TimeRange)
        /// A clip's voice level, in dB, from dragging its line (docs/decisions.md, 71).
        case setVoiceLevel(ClipID, Double)
        case select(EditorSelection)
        case click(Hit)
    }
    public private(set) var state: State = .idle
    public var drag: DragState? { if case .active(_, let drag) = state { drag } else { nil } }
    public init() {}

    /// An immutable view of the current edit and pointer geometry for one event.
    public struct Context: Sendable {
        public let edit: Edit
        public let timeline: EditTimeline
        public let zoom: Double
        public let snapping: Bool
        public let selection: EditorSelection
        public let tool: TimelineTool
        public let playhead: TimeInterval
        public let snapper: EditSnapper
        public let frameDuration: TimeInterval
        public let sourceDurations: [SourceID: TimeInterval]
        public init(edit: Edit, transcripts: TranscriptIndex,
                    zoom: Double, snapping: Bool, selection: EditorSelection, tool: TimelineTool,
                    playhead: TimeInterval, snapper: EditSnapper, frameDuration: TimeInterval = 1.0 / 30,
                    sourceDurations: [SourceID: TimeInterval] = [:]) {
            self.init(edit: edit, timeline: EditTimeline(edit: edit, transcripts: transcripts),
                      zoom: zoom, snapping: snapping, selection: selection, tool: tool, playhead: playhead, snapper: snapper,
                      frameDuration: frameDuration, sourceDurations: sourceDurations)
        }

        /// Uses projections already made for this edit revision. Pointer movement does not need to
        /// rebuild the timeline or the source snapping index.
        public init(edit: Edit, timeline: EditTimeline, zoom: Double, snapping: Bool,
                    selection: EditorSelection, tool: TimelineTool, playhead: TimeInterval, snapper: EditSnapper,
                    frameDuration: TimeInterval = 1.0 / 30, sourceDurations: [SourceID: TimeInterval] = [:]) {
            self.edit = edit
            self.timeline = timeline
            self.zoom = zoom.isFinite && zoom > 0 ? zoom : 1
            self.snapping = snapping
            self.selection = selection
            self.tool = tool
            self.playhead = playhead
            self.snapper = snapper
            self.frameDuration = frameDuration.isFinite && frameDuration > 0 ? frameDuration : 1.0 / 30
            self.sourceDurations = sourceDurations
        }
        public func time(_ x: Double) -> TimeInterval { max(0, (x - TimelineLane.leading) / zoom) }
        public func snapped(_ time: TimeInterval, tolerance: TimeInterval) -> TimeInterval {
            if snapping {
                let snapped = snapper.snap(time, in: edit, tolerance: tolerance, extra: [playhead])
                if snapped.target != nil { return snapped.time }
            }
            return Timecode(frameDuration: frameDuration).frameTime(nearest: time)
        }
    }

    public enum DragState: Equatable, Sendable {
        case scrub
        /// An edge being dragged. `rolls` when the Trim tool was pressed on a join that rolls: the join then
        /// follows the pointer either way, and `clip` and `edge` are whichever side is moving outward.
        case edge(clip: ClipID, edge: ClipEdge, source: SourceID, start: TimeInterval, rate: Double, x: Double, current: TimeInterval, snapped: Bool, rolls: Bool)
        case overlay(id: ClipID, part: Part, range: TimeRange, x: Double, current: TimeRange)
        case freeze(id: FreezeID, edge: ClipEdge, range: TimeRange, rate: Double, x: Double, current: TimeRange)
        /// A clip's voice level line, dragged up or down, in dB.
        case level(clip: ClipID, start: Double, current: Double)
        case click(Hit)
    }

    public enum Part: Equatable, Sendable { case body, start, end }

    /// What's under the pointer.
    public enum Hit: Equatable, Sendable {
        case ruler
        case overlay(ClipID, Part)
        case clip(ClipID, edge: ClipEdge?)
        case freeze(FreezeID, edge: ClipEdge?)
        /// A clip's voice level line in the audio lane.
        case voiceLevel(ClipID)
        case empty
    }

    public func hit(_ point: CGPoint, in context: Context) -> Hit {
        let edit = context.edit
        let timeline = context.timeline
        guard let lane = TimelineLane.at(y: point.y) else { return .ruler }
        let t = context.time(point.x)
        let grab = 6 / context.zoom
        switch lane {
        case .overlays:
            for placed in timeline.overlays.reversed() where placed.timeline.start - grab <= t && t <= placed.timeline.end + grab {
                if abs(t - placed.timeline.start) <= grab { return .overlay(placed.overlay.id, .start) }
                if abs(t - placed.timeline.end) <= grab { return .overlay(placed.overlay.id, .end) }
                return .overlay(placed.overlay.id, .body)
            }
            return .empty
        case .video:
            let bandTop = TimelineLane.video.top + TimelineLane.video.height - 18
            if point.y >= bandTop {
                for freeze in edit.freezes.reversed() {
                    for piece in edit.timelinePieces(of: freeze.range, in: freeze.source) where piece.timeline.start - grab <= t && t <= piece.timeline.end + grab {
                        if abs(t - piece.timeline.start) <= grab { return .freeze(freeze.id, edge: .start) }
                        if abs(t - piece.timeline.end) <= grab { return .freeze(freeze.id, edge: .end) }
                        return .freeze(freeze.id, edge: nil)
                    }
                }
            }
            // The edges within reach. At a join, where one clip's end meets the next one's start, the selected
            // clip's edge wins, then the edge of the clip the pointer is over.
            // At fit scale a short clip can be narrower than the two edge hit areas together. Keep its
            // body selectable; zooming in, T, or an explicitly selected edge still permits trimming it.
            let pickedEdgeTime = context.selection.edge.flatMap { picked in
                timeline.clips.first(where: { $0.clip.id == picked.clip }).map {
                    picked.edge == .start ? $0.timeline.start : $0.timeline.end
                }
            }
            if context.tool == .select,
               let containing = timeline.clips.first(where: { $0.timeline.start <= t && t < $0.timeline.end }),
               pickedEdgeTime.map({ abs(t - $0) > grab }) ?? true,
               containing.timeline.duration * context.zoom < 24 {
                return .clip(containing.clip.id, edge: nil)
            }
            let selected = context.selection.clipIDs
            var reachable: [(clip: ClipID, edge: ClipEdge, distance: Double, isOver: Bool)] = []
            for placed in timeline.clips {
                let fromStart = abs(t - placed.timeline.start)
                if fromStart <= grab { reachable.append((placed.clip.id, .start, fromStart, t >= placed.timeline.start)) }
                let fromEnd = abs(t - placed.timeline.end)
                if fromEnd <= grab { reachable.append((placed.clip.id, .end, fromEnd, t < placed.timeline.end)) }
            }
            if let nearest = reachable.min(by: { a, b in
                if abs(a.distance - b.distance) > 1e-9 { return a.distance < b.distance }
                let aSelected = selected.contains(a.clip), bSelected = selected.contains(b.clip)
                if aSelected != bSelected { return aSelected }
                if a.isOver != b.isOver { return a.isOver }
                return a.distance < b.distance
            }) {
                return .clip(nearest.clip, edge: nearest.edge)
            }
            if let containing = timeline.clips.first(where: { $0.timeline.start <= t && t < $0.timeline.end }) {
                return .clip(containing.clip.id, edge: context.tool == .trim ? (t - containing.timeline.start < containing.timeline.end - t ? .start : .end) : nil)
            }
            return .empty
        case .audio:
            if let containing = timeline.clips.first(where: { $0.timeline.start <= t && t < $0.timeline.end }) {
                if context.tool != .blade, abs(point.y - AudioLane.lineY(for: containing.clip.voiceLevel)) <= AudioLane.grab {
                    return .voiceLevel(containing.clip.id)
                }
                return .clip(containing.clip.id, edge: nil)
            }
            return .empty
        }
    }

    /// Returns a playhead update while scrubbing. A changed revision cancels until mouse-up.
    public mutating func changed(from origin: CGPoint, to point: CGPoint, in context: Context) -> TimeInterval? {
        if case .active(let revision, _) = state, revision != context.edit.revision { state = .cancelled }
        if case .cancelled = state { return nil }
        var drag = self.drag
        defer { if let drag { state = .active(revision: context.edit.revision, drag: drag) } }
        if drag == nil {
            let target = hit(origin, in: context)
            switch target {
            case .ruler, .empty:
                drag = .scrub
            case .clip(let id, let edge?) where context.tool != .blade:
                guard let clip = context.edit.main.first(where: { $0.id == id }) else { return nil }
                let start = edge == .start ? clip.playedRange.start : clip.playedRange.end
                // A join rolls only with the Trim tool, pressed on the join itself. Anywhere else on a clip the
                // Trim tool takes the nearer edge and trims it, as the Select tool does at an edge.
                var rolls = false
                if context.tool == .trim, context.edit.isRollable(edge, of: id),
                   let placed = context.timeline.clips.first(where: { $0.clip.id == id }) {
                    let join = edge == .start ? placed.timeline.start : placed.timeline.end
                    rolls = abs(context.time(origin.x) - join) <= 6 / context.zoom
                }
                drag = .edge(clip: id, edge: edge, source: clip.source, start: start, rate: clip.speed.rate, x: origin.x, current: start, snapped: false, rolls: rolls)
            case .overlay(let id, let part):
                guard let range = context.timeline.overlays.first(where: { $0.overlay.id == id })?.timeline else { return nil }
                drag = .overlay(id: id, part: part, range: range, x: origin.x, current: range)
            case .freeze(let id, let edge?):
                guard let freeze = context.edit.freezes.first(where: { $0.id == id }) else { return nil }
                let time = context.time(origin.x)
                let rate = context.timeline.clips.first {
                    $0.clip.source == freeze.source && $0.timeline.start <= time && time <= $0.timeline.end
                        && $0.clip.playedRange.overlaps(freeze.range)
                }?.clip.speed.rate ?? 1
                drag = .freeze(id: id, edge: edge, range: freeze.range, rate: rate, x: origin.x, current: freeze.range)
            case .voiceLevel(let id):
                guard let clip = context.edit.main.first(where: { $0.id == id }) else { return nil }
                drag = .level(clip: id, start: clip.voiceLevel, current: clip.voiceLevel)
            default:
                drag = .click(target)
            }
        }
        let delta = (point.x - origin.x) / context.zoom
        switch drag {
        case .scrub:
            return context.snapped(context.time(point.x), tolerance: 5 / context.zoom)
        case .edge(var clip, var edge, let source, let start, var rate, let x, _, _, let rolls):
            // A rolling join follows the pointer: earlier, the later clip's start moves out; later, the
            // earlier clip's end does. Either way the other edge goes with it.
            if rolls, delta != 0, let pair = context.edit.rollingPair(edge, of: clip) {
                let moving = delta < 0 ? pair.after : pair.before
                (clip, edge, rate) = (moving.id, delta < 0 ? .start : .end, moving.speed.rate)
            }
            var target = start + delta * rate
            var snapped = false
            if context.snapping, let stuck = context.snapper.snap(sourceTime: target, in: source, tolerance: 8 / context.zoom * rate) {
                target = stuck.time
                snapped = true
            }
            if !snapped, let placed = context.timeline.clips.first(where: { $0.clip.id == clip }) {
                let frame = Timecode(frameDuration: context.frameDuration).frameTime(nearest: placed.timelineTime(ofSourceTime: target))
                target = placed.sourceTime(at: frame)
            }
            if let bounds = context.edit.edgeRange(edge, of: clip, sourceDuration: context.sourceDurations[source], rolling: rolls) {
                let limited = min(max(bounds.lowerBound, target), bounds.upperBound)
                if limited != target { snapped = false }
                target = limited
            }
            drag = .edge(clip: clip, edge: edge, source: source, start: start, rate: rate, x: x, current: target, snapped: snapped, rolls: rolls)
        case .overlay(let id, let part, let range, let x, _):
            var shifted = range
            switch part {
            case .body: shifted = TimeRange(start: max(0, range.start + delta), end: max(0, range.start + delta) + range.duration)
            case .start: shifted.start = min(range.end - 0.1, max(0, range.start + delta))
            case .end: shifted.end = max(range.start + 0.1, range.end + delta)
            }
            if context.snapping {
                let edge = part == .end ? shifted.end : shifted.start
                let snapped = context.snapped(edge, tolerance: 8 / context.zoom) - edge
                if part != .end { shifted.start += snapped }
                if part != .start { shifted.end += snapped }
            }
            switch part {
            case .body:
                shifted.start = max(0, shifted.start)
                shifted.end = shifted.start + range.duration
            case .start: shifted.start = min(range.end - 0.1, max(0, shifted.start))
            case .end: shifted.end = max(range.start + 0.1, shifted.end)
            }
            drag = .overlay(id: id, part: part, range: range, x: x, current: shifted)
        case .freeze(let id, let edge, let range, let rate, let x, _):
            var current = range
            if edge == .start { current.start = min(range.end - 0.05, max(0, range.start + delta * rate)) }
            else { current.end = max(range.start + 0.05, range.end + delta * rate) }
            drag = .freeze(id: id, edge: edge, range: range, rate: rate, x: x, current: current)
        case .level(let clip, let start, _):
            // The line moves with the pointer from where it was, wherever on it the press landed.
            let current = AudioLane.level(atY: AudioLane.lineY(for: start) + point.y - origin.y)
            drag = .level(clip: clip, start: start, current: current)
        default:
            break
        }
        return nil
    }

    /// Commits at most one edit operation, with any resulting selection, then returns to idle.
    public mutating func ended(from origin: CGPoint, to point: CGPoint, in context: Context) -> [Action] {
        defer { state = .idle }
        guard case .active(let revision, let drag) = state, revision == context.edit.revision else { return [] }
        var actions: [Action] = []
        let moved = abs(point.x - origin.x) > 3
        switch drag {
        case .edge(let clip, let edge, _, let start, _, _, let current, _, let rolls):
            if moved, abs(current - start) > 0.001 {
                actions.append(.trim(clip, edge, current, rolling: rolls))
            } else {
                actions.append(.select(.clipEdge(clip: clip, edge: edge)))
            }
        case .overlay(let id, _, let range, _, let current):
            if moved, current != range {
                actions.append(.moveOverlay(id, current))
            }
            actions.append(.select(.overlays([id])))
        case .freeze(let id, _, let range, _, _, let current):
            if moved, current != range { actions.append(.stretchFreeze(id, current)) }
            actions.append(.select(.freeze(id)))
        case .level(let clip, let start, let current):
            if abs(point.y - origin.y) > 1, current != start {
                actions.append(.setVoiceLevel(clip, current))
                actions.append(.select(.clips([clip])))
            } else {
                actions.append(.click(.clip(clip, edge: nil)))
            }
        case .click(let target):
            actions.append(.click(target))
        case .scrub:
            if !moved, TimelineLane.at(y: origin.y) != nil { actions.append(.select(.none)) }
        }
        return actions
    }
}

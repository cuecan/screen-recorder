import ProjectKit
import RenderKit
import SwiftUI

/// Timeline content that changes with edits, selection and scrolling. Playback's moving playhead is
/// drawn separately, so it does not redraw waveforms or lay out words on every playback tick.
struct TimelineDrawing: View {
    let model: EditorModel
    let drag: TimelineInteraction.DragState?
    let viewport: TimelineViewport

    typealias DragState = TimelineInteraction.DragState
    private static let leading = TimelineView.leading
    private static let ruler = TimelineView.ruler
    private static let lanes = TimelineView.lanes

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: -viewport.offset, y: 0)
            draw(&context, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func x(_ time: TimeInterval) -> Double { Self.leading + time * model.zoom }
    private func time(_ x: Double) -> TimeInterval { max(0, (x - Self.leading) / model.zoom) }
    private func laneTop(_ index: Int) -> Double { Self.lanes[index].top }

    // MARK: - Drawing

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard let edit = model.edit, let timeline = model.timeline else {
            // While the take loads there's nothing to say; once loaded, an empty timeline was emptied on purpose.
            if model.edit?.main.isEmpty == true, !model.isPreparing {
                context.draw(Text("The timeline is empty").font(.callout).foregroundStyle(.secondary), at: CGPoint(x: viewport.offset + size.width / 2, y: size.height / 2))
            }
            return
        }
        drawRuler(&context, size: size, edit: edit)
        for index in Self.lanes.indices {
            let top = laneTop(index) + Self.lanes[index].height
            context.fill(Path(CGRect(x: viewport.offset, y: top - 0.5, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.25)))
        }
        drawOverlays(&context, timeline: timeline)
        drawClips(&context, timeline: timeline, edit: edit)
        drawAudio(&context, timeline: timeline)
        drawWords(&context)
        drawMarks(&context, size: size)
    }

    private func drawRuler(_ context: inout GraphicsContext, size: CGSize, edit: Edit) {
        // A tick every so many seconds, so labels don't crowd.
        let steps: [Double] = [0.1, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
        let step = steps.first { $0 * model.zoom >= 60 } ?? 7200
        var t = max(0, floor(time(viewport.drawingBounds.lowerBound) / step) * step)
        while x(t) < viewport.drawingBounds.upperBound {
            let tickX = x(t)
            context.fill(Path(CGRect(x: tickX, y: Self.ruler - 8, width: 0.5, height: 8)), with: .color(.secondary))
            context.draw(Text(Self.rulerLabel(t, step: step)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: tickX + 3, y: 7), anchor: .leading)
            let minor = x(t + step / 2)
            context.fill(Path(CGRect(x: minor, y: Self.ruler - 4, width: 0.5, height: 4)), with: .color(.secondary.opacity(0.6)))
            t += step
        }
        // Dots where the screen went still (docs/decisions.md, 58).
        for (source, moments) in model.stillMoments {
            for moment in moments {
                for piece in edit.timelinePieces(of: TimeRange(start: moment, end: moment + 0.001), in: source) {
                    let dot = CGRect(x: x(piece.timeline.start) - 2.5, y: Self.ruler - 13, width: 5, height: 5)
                    guard isVisible(dot) else { continue }
                    context.fill(Path(ellipseIn: dot), with: .color(.accentColor.opacity(0.8)))
                }
            }
        }
        for marker in model.markers {
            let markerX = x(marker)
            guard viewport.drawingBounds.contains(markerX) else { continue }
            context.fill(Path { path in
                path.move(to: CGPoint(x: markerX - 4, y: 2))
                path.addLine(to: CGPoint(x: markerX + 4, y: 2))
                path.addLine(to: CGPoint(x: markerX, y: 9))
                path.closeSubpath()
            }, with: .color(.orange))
        }
        context.fill(Path(CGRect(x: viewport.offset, y: Self.ruler - 0.5, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.4)))
    }

    static func rulerLabel(_ t: TimeInterval, step: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        return step < 1 ? String(format: "%d:%04.1f", minutes, seconds) : String(format: "%d:%02d", minutes, Int(seconds.rounded()))
    }

    /// "[" on a clip's start, "]" on its end, so a join that rolls reads as "][".
    private func drawBracket(_ context: inout GraphicsContext, _ edge: ClipEdge, of rect: CGRect, color: Color, width: Double) {
        let edgeX = edge == .start ? rect.minX + width / 2 : rect.maxX - width / 2
        let tick = 6.0 * (edge == .start ? 1 : -1)
        let top = rect.minY - 2
        let bottom = rect.maxY + 2
        let path = Path { path in
            path.move(to: CGPoint(x: edgeX + tick, y: top))
            path.addLine(to: CGPoint(x: edgeX, y: top))
            path.addLine(to: CGPoint(x: edgeX, y: bottom))
            path.addLine(to: CGPoint(x: edgeX + tick, y: bottom))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .square, lineJoin: .miter))
    }

    private func drawOverlays(_ context: inout GraphicsContext, timeline: EditTimeline) {
        let top = laneTop(0) + 5
        let height = Self.lanes[0].height - 10
        for placed in timeline.overlays {
            var range = placed.timeline
            if case .overlay(let id, _, _, _, let current) = drag, id == placed.overlay.id { range = current }
            let rect = CGRect(x: x(range.start), y: top, width: max(4, range.duration * model.zoom), height: height)
            guard isVisible(rect) else { continue }
            let selected = model.selection.overlayIDs.contains(placed.overlay.id)
            let path = Path(roundedRect: rect, cornerRadius: 5)
            context.fill(path, with: .color(placed.overlay.isStill ? .teal.opacity(0.55) : .indigo.opacity(0.55)))
            context.stroke(path, with: .color(selected ? .yellow : .black.opacity(0.35)), lineWidth: selected ? 2 : 1)
            var label = model.displayName(of: placed.overlay)
            if placed.overlay.placement == .inScreensPlace { label += " · screen’s place" }
            if placed.overlay.playsSound { label += " · sound" }
            draw(&context, label, in: rect)
        }
    }

    private func drawClips(_ context: inout GraphicsContext, timeline: EditTimeline, edit: Edit) {
        let top = laneTop(1) + 4
        let height = Self.lanes[1].height - 8
        // The edge being dragged, or else the one selected, for the yellow brackets.
        var picked = model.selection.edge
        // Both sides of a join light up only where moving it moves both: the Trim tool, or a drag that rolls.
        var rollsTogether = model.tool == .trim
        if case .edge(let id, let edge, _, _, _, _, _, _, let rolls) = drag { picked = (id, edge); rollsTogether = rolls }
        for placed in timeline.clips {
            let clip = placed.clip
            let played = clip.playedRange
            let index = placed.index
            let rollsBefore = edit.joinRolls(after: index - 1)
            let rollsAfter = edit.joinRolls(after: index)
            var range = placed.timeline
            if case .edge(let id, let edge, _, _, let rate, _, let current, _, let rolls) = drag {
                if id == clip.id {
                    // A ghost of where the edge will land.
                    if edge == .end { range.end = placed.timeline.start + (current - played.start) / rate }
                    else { range.start = placed.timeline.end - (played.end - current) / rate }
                } else if rolls, edge == .start, rollsAfter, index + 1 < edit.main.count, edit.main[index + 1].id == id, current < played.end {
                    // At a join that rolls, the neighbour gives way.
                    range.end = placed.timeline.start + (current - played.start) / clip.speed.rate
                } else if rolls, edge == .end, rollsBefore, index > 0, edit.main[index - 1].id == id, current > played.start {
                    range.start = placed.timeline.end - (played.end - current) / clip.speed.rate
                }
            }
            let rect = CGRect(x: x(range.start) + 1, y: top, width: max(3, range.duration * model.zoom - 2), height: height)
            guard isVisible(rect) else { continue }
            let selected = model.selection.clipIDs.contains(clip.id)
            let path = Path(roundedRect: rect, cornerRadius: 5)
            // A selected clip is a deeper blue as well as outlined, so it reads at a glance in either appearance.
            context.fill(path, with: .color(clip.isMuted ? .gray.opacity(selected ? 0.75 : 0.5) : .blue.opacity(selected ? 0.9 : 0.55)))
            context.stroke(path, with: .color(selected ? .yellow : .black.opacity(0.35)), lineWidth: selected ? 2 : 1)
            var label = layoutLabel(clip)
            if !clip.speed.isNormal { label = "\(clip.speed.label) · " + label }
            // Numbered as the inspector's breadcrumbs name it ("Clip 2").
            label = "\(index + 1)  " + label
            let hasCaptionBadge = clip.look.captions && rect.width >= 46
            var labelRect = rect.offsetBy(dx: 0, dy: -height / 4)
            if hasCaptionBadge { labelRect.size.width -= 24 }
            draw(&context, label, in: labelRect, color: selected ? .white : .primary)
            if hasCaptionBadge {
                let badge = CGRect(x: rect.maxX - 23, y: rect.minY + 6, width: 18, height: 12)
                let ink = selected ? Color.white : Color.primary.opacity(0.8)
                context.stroke(Path(roundedRect: badge, cornerRadius: 2), with: .color(ink.opacity(0.7)), lineWidth: 0.75)
                context.draw(Text("CC").font(.system(size: 7, weight: .semibold)).foregroundStyle(ink),
                             at: CGPoint(x: badge.midX, y: badge.midY))
            }
            // A small marker on an edge placed by hand.
            for edge in ClipEdge.allCases where clip.isPlacedByHand(edge) {
                let edgeX = edge == .start ? rect.minX + 1 : rect.maxX - 1
                let direction = edge == .start ? 1.0 : -1.0
                context.fill(Path { path in
                    path.move(to: CGPoint(x: edgeX, y: rect.minY + 2))
                    path.addLine(to: CGPoint(x: edgeX + 7 * direction, y: rect.minY + 2))
                    path.addLine(to: CGPoint(x: edgeX, y: rect.minY + 9))
                    path.closeSubpath()
                }, with: .color(.white.opacity(0.9)))
            }
            // Brackets: ][ at a join that rolls, in the text colour; yellow on the picked edge, and on both sides of a
            // join that rolls when either side is picked with the Trim tool, since that moves both.
            for edge in ClipEdge.allCases {
                let rolls = edge == .start ? rollsBefore : rollsAfter
                var isPicked = picked.map { $0.clip == clip.id && $0.edge == edge } ?? false
                if rolls, rollsTogether, let picked {
                    let neighbour = edge == .start ? edit.main[index - 1].id : edit.main[index + 1].id
                    isPicked = isPicked || (picked.clip == neighbour && picked.edge != edge)
                }
                if isPicked {
                    drawBracket(&context, edge, of: rect, color: .yellow, width: 2.5)
                } else if rolls {
                    drawBracket(&context, edge, of: rect, color: .primary.opacity(0.55), width: 1.5)
                }
            }
        }
        // Freezes: a band along the bottom of the video lane, over the stretch that holds.
        for freeze in edit.freezes {
            for piece in edit.timelinePieces(of: freeze.range, in: freeze.source) {
                var range = piece.timeline
                if case .freeze(let id, _, _, _, _, let current) = drag, id == freeze.id {
                    range = TimeRange(start: piece.timeline.start + (current.start - freeze.range.start), end: piece.timeline.end + (current.end - freeze.range.end))
                }
                let band = CGRect(x: x(range.start), y: top + height - 14, width: max(3, range.duration * model.zoom), height: 14)
                guard isVisible(band) else { continue }
                let selected = model.selection.freezeID == freeze.id
                context.fill(Path(roundedRect: band, cornerRadius: 3), with: .color(.orange.opacity(0.85)))
                if selected { context.stroke(Path(roundedRect: band, cornerRadius: 3), with: .color(.yellow), lineWidth: 2) }
                context.draw(Text("Hold").font(.system(size: 9, weight: .semibold)).foregroundStyle(.black), at: CGPoint(x: band.minX + 4, y: band.midY), anchor: .leading)
            }
        }
    }

    /// The voice's waveform with each clip's level line across it, and system audio's thinner waveform under it
    /// (docs/decisions.md, 71).
    private func drawAudio(_ context: inout GraphicsContext, timeline: EditTimeline) {
        let top = laneTop(2)
        let height = Self.lanes[2].height
        let voice = AudioLane.voice, system = AudioLane.system
        guard let project = model.project else { return }
        for placed in timeline.clips {
            let clip = placed.clip
            let soundSource = clip.audio?.source ?? clip.source
            let silent = clip.isMuted || clip.speed.sound == .muted
            let left = x(placed.timeline.start)
            let right = x(placed.timeline.end)
            guard left <= viewport.drawingBounds.upperBound, right >= viewport.drawingBounds.lowerBound else { continue }
            let box = CGRect(x: left + 1, y: top + 2, width: max(2, right - left - 2), height: height - 4)
            context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.green.opacity(silent ? 0.05 : 0.12)))
            var level = clip.voiceLevel
            var dragging = false
            if case .level(let id, _, let current) = drag, id == clip.id { level = current; dragging = true }
            if dragging { context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(.yellow), lineWidth: 2) }
            guard project.source(soundSource) != nil else { continue }
            if !silent, let waveform = model.waveforms[soundSource] {
                bars(&context, waveform, placed: placed, gain: level, from: left, to: right, in: voice, color: .green.opacity(0.8))
            }
            // System audio plays only with the clip's own mic.
            if !silent, clip.audio == nil, let waveform = model.systemWaveforms[clip.source] {
                context.fill(Path(CGRect(x: left + 1, y: system.lowerBound - 1, width: max(2, right - left - 2), height: 0.5)),
                             with: .color(.primary.opacity(0.12)))
                bars(&context, waveform, placed: placed, gain: clip.systemAudioLevel, from: left, to: right, in: system, color: .gray.opacity(0.9))
            }
            // The voice's level, a line across the clip to drag up or down: a faint hairline, so it sits behind
            // the waveform until it's wanted (as asked: "way too thick... a lot more subtle"). It thickens
            // and turns yellow while it's dragged.
            let lineY = AudioLane.lineY(for: level)
            let width = max(2, right - left - 2)
            let thickness = dragging ? 2.0 : 1.0
            context.fill(Path(CGRect(x: left + 1, y: lineY - thickness / 2, width: width, height: thickness)),
                         with: .color(dragging ? .yellow : .primary.opacity(silent ? 0.15 : 0.3)))
        }
    }

    /// A waveform's bars over a clip, centred in a band of the audio lane.
    private func bars(_ context: inout GraphicsContext, _ waveform: Waveform, placed: EditTimeline.PlacedClip, gain: Double,
                      from left: Double, to right: Double, in band: ClosedRange<Double>, color: Color) {
        let middle = (band.lowerBound + band.upperBound) / 2
        let reach = (band.upperBound - band.lowerBound) / 2 - 1
        var path = Path()
        for barX in viewport.waveformBars(from: left, to: right) {
            let from = placed.sourceTime(at: time(barX))
            let to = placed.sourceTime(at: time(barX + 2))
            let fraction = WaveformScale.height(peak: Double(waveform.peak(from: from, to: to)), gain: gain)
            guard fraction > 0 else { continue }
            let half = max(0.5, fraction * reach)
            path.addRect(CGRect(x: barX, y: middle - half, width: 1.5, height: half * 2))
        }
        context.fill(path, with: .color(color))
    }

    /// Each played word's name just under the voice's waveform wherever its label fits, with a faint
    /// tick up through the wave (docs/decisions.md, 74). The times are fitted to the audio when the take is
    /// transcribed, so a word never starts in a silence. Words picked in the transcript are shaded at any zoom.
    /// Nothing here is clicked: the transcript is where words are picked and fixed.
    private func drawWords(_ context: inout GraphicsContext) {
        let band = AudioLane.words, voice = AudioLane.voice
        let visible = viewport.timeRange(zoom: model.zoom)
        let words = model.playedWords.filter { $0.range.end >= visible.start && $0.range.start <= visible.end }
        if let range = model.selection.wordRange, let picked = selectedWordIDs(range) {
            for word in words where picked.contains(word.id) {
                let rect = CGRect(x: x(word.range.start), y: band.lowerBound, width: max(2, word.range.duration * model.zoom),
                                  height: band.upperBound - band.lowerBound)
                context.fill(Path(rect), with: .color(.yellow.opacity(0.4)))
            }
        }
        for (index, word) in words.enumerated() {
            let left = x(word.range.start)
            // A name may run on past its word into a pause, but never into the next word.
            let limit = index + 1 < words.count ? x(words[index + 1].range.start) : left + 300
            if limit - left >= 4 {
                context.fill(Path(CGRect(x: left, y: voice.lowerBound, width: 0.5, height: band.upperBound - voice.lowerBound)),
                             with: .color(.primary.opacity(0.16)))
            }
            guard limit - left >= 12 else { continue }
            var inner = context
            inner.clip(to: Path(CGRect(x: left + 1, y: band.lowerBound, width: limit - left - 3, height: band.upperBound - band.lowerBound)))
            inner.draw(Text(word.text.isEmpty ? "·" : word.text).font(.system(size: 10)).foregroundStyle(.primary.opacity(0.7)),
                       at: CGPoint(x: left + 3, y: (band.lowerBound + band.upperBound) / 2), anchor: .leading)
        }
    }

    private func drawMarks(_ context: inout GraphicsContext, size: CGSize) {
        if model.selection.isEmpty, let range = model.markedRange {
            let rect = CGRect(x: x(range.start), y: 0, width: range.duration * model.zoom, height: size.height)
            context.fill(Path(rect), with: .color(.yellow.opacity(0.12)))
            context.stroke(Path(rect.insetBy(dx: 0, dy: 1)), with: .color(.yellow), lineWidth: 2)
        }
        for mark in [model.markIn, model.markOut].compactMap({ $0 }) {
            context.fill(Path(CGRect(x: x(mark) - 0.5, y: 0, width: 1, height: size.height)), with: .color(.accentColor))
        }
    }

    private func draw(_ context: inout GraphicsContext, _ text: String, in rect: CGRect, color: Color = .primary) {
        guard rect.width > 18 else { return }
        var inner = context
        inner.clip(to: Path(rect.insetBy(dx: 4, dy: 0)))
        inner.draw(Text(text).font(.caption).foregroundStyle(color), at: CGPoint(x: max(rect.minX + 6, viewport.offset + 6), y: rect.midY), anchor: .leading)
    }

    private func isVisible(_ rect: CGRect) -> Bool {
        rect.maxX >= viewport.drawingBounds.lowerBound && rect.minX <= viewport.drawingBounds.upperBound
    }

    private func layoutLabel(_ clip: Clip) -> String {
        guard let source = model.project?.source(clip.source) else { return clip.id.description }
        let pictures = ClipPictures(source: source)
        // A clip has one layout (docs/decisions.md, 77), named as the shape shown draws it.
        return LayoutGeometry.resolved(clip.layout, in: model.shape, pictures: pictures).name
    }

    // MARK: - Words

    private func selectedWordIDs(_ range: ItemRange) -> Set<WordID>? {
        guard let transcript = try? model.transcripts.transcript(containing: range),
            let indices = try? CutPointSnapper(transcript: transcript).indices(of: range)
        else { return nil }
        return Set(transcript.items[indices].compactMap { if case .word(let word) = $0 { word.id } else { nil } })
    }

}

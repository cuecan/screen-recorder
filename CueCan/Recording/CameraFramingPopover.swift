import AVFoundation
import AppKit
import Observation
import ProjectKit
import RecorderKit
import RenderKit
import SwiftUI

/// What the framing popover frames: the Recording Panel's live camera, or a recorded camera in the editor
/// (docs/ui.md, R8 and E5; docs/decisions.md, 52). The popover's look and gestures are the same for both.
@MainActor
protocol FramingSource: AnyObject {
    /// The camera's picture as recorded, in pixels.
    var cameraPictureSize: CGSize { get }
    /// What to show: the live camera, or a frame of the recorded one.
    var framingPicture: FramingPicture { get }
    /// The framing a slot shows now.
    func shownFraming(_ slot: CameraSlot) -> CameraFraming
    /// Changes a slot's framing. Called continuously while dragging, scrolling or sliding.
    func setFraming(_ framing: CameraFraming, slot: CameraSlot)
    /// A drag or a zoom finished: a source that saves each change as an edit saves it now.
    func framingEnded(slot: CameraSlot)
    /// Reset: back to the middle, not zoomed, unless the source has a framing of its own to go back to.
    func resetFraming(slot: CameraSlot)
    /// The camera placements in a slot, in each output the slot is in, from the same layouts the export uses.
    func cameraPlacements(in slot: CameraSlot) -> [(output: OutputShape, placement: Placement)]
    /// The one shape whose crop is outlined, named beside the title: the editor's, for a take made for both.
    /// Nil when every shape's crop shows, as while setting up.
    var shapeShown: OutputShape? { get }
}

extension FramingSource {
    func framingEnded(slot: CameraSlot) {}

    var shapeShown: OutputShape? { nil }

    func resetFraming(slot: CameraSlot) {
        setFraming(.centered, slot: slot)
    }
}

/// The camera picture behind the popover's outlines.
enum FramingPicture {
    /// The live camera, mirrored as the Recording Panel shows it.
    case live(CameraPreviewFeed)
    /// A frame of the recorded camera, as recorded, not mirrored; nil while it loads.
    case still(CGImage?)
}

/// The camera framing popover (docs/ui.md, R8; docs/decisions.md, 52), beside the editor's inspector.
/// While setting up, framing happens in the setup element's well instead (R10, `WellFramingView`). It frames one kind of camera slot at a time, with tabs for
/// the slots the format uses: the whole camera frame with that slot's crop outlined and the rest dimmed, a
/// zoom slider with Reset beside it, and a close button. Drag to move; pinch, scroll or the slider to zoom.
/// The close button, clicking away or Esc closes it.
final class CameraFramingPopover {
    private unowned let source: any FramingSource
    private let presentation = TransientPanel()
    private let target = FramingTarget()

    init(source: any FramingSource) {
        self.source = source
    }

    var isOpen: Bool { presentation.isOpen }
    /// The slot being framed, while it's open.
    var slot: CameraSlot? { isOpen ? target.slot : nil }

    /// Opens beside `anchor` (in screen coordinates), to its right if there's room, otherwise to its left,
    /// on one kind of slot. With more than one slot in `tabs`, it shows them as tabs.
    func open(beside anchor: CGRect, slot: CameraSlot, tabs: [CameraSlot]) {
        let panel = makePanel(slot: slot, tabs: tabs)
        let size = panel.fittingSize
        let visible = NSScreen.holding(anchor)?.visibleFrame ?? anchor
        let right = CGRect(x: anchor.maxX + 12, y: anchor.maxY - size.height, width: size.width, height: size.height)
        let left = CGRect(x: anchor.minX - 12 - size.width, y: right.minY, width: size.width, height: size.height)
        let frame = right.maxX <= visible.maxX || left.minX < visible.minX ? right : left
        presentation.open(panel, frame: AreaGeometry.clamped(frame, to: visible))
    }

    private func makePanel(slot: CameraSlot, tabs: [CameraSlot]) -> OverlayPanel {
        close()
        target.slot = slot
        target.tabs = tabs.count > 1 ? tabs : []
        target.close = { [weak self] in self?.close() }
        let panel = OverlayPanel.hosting(CameraFramingView(source: source, target: target), level: .popUpMenu, takesKeyboard: true)
        panel.hasShadow = true
        return panel
    }

    func close() {
        if let slot { source.framingEnded(slot: slot) }
        presentation.close()
    }
}

/// Which slot the popover frames, and the tabs it offers.
@Observable
final class FramingTarget {
    var slot = CameraSlot.card
    var tabs: [CameraSlot] = []
    @ObservationIgnored var close: () -> Void = {}
}

/// The popover's content.
struct CameraFramingView: View {
    let source: any FramingSource
    let target: FramingTarget
    /// Show the whole selected camera at its native aspect ratio.
    private var frameSize: CGSize {
        CGSize(width: 432, height: 432 * source.cameraPictureSize.height / max(source.cameraPictureSize.width, 1))
    }

    private var framing: CameraFraming { source.shownFraming(target.slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Camera framing").fontWeight(.semibold)
                // With tabs, they name the slot; without, the slot is named here.
                if target.tabs.isEmpty {
                    Text(target.slot.label)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                // One framing for both shapes: this says whose crop is outlined (docs/decisions.md, 77).
                if let shape = source.shapeShown {
                    Text(shape.previewLabel)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .help("The outline is this shape’s crop.")
                }
                Spacer(minLength: 0)
                // Closes it, keeping the framing as it is, like clicking away.
                Button {
                    target.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.1), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }
            .frame(height: 24)

            if !target.tabs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(target.tabs, id: \.self) { slot in
                        let isOn = slot == target.slot
                        Button {
                            source.framingEnded(slot: target.slot)
                            target.slot = slot
                        } label: {
                            Text(slot.label)
                                .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? .white : .white.opacity(0.65))
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(isOn ? .white.opacity(0.18) : .clear, in: .rect(cornerRadius: 6))
                                .contentShape(.rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Which camera slot")
            }

            FramingFrame(source: source, slot: target.slot, size: frameSize)
                .frame(width: frameSize.width, height: frameSize.height)
                .clipShape(.rect(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.7))
                Slider(value: Binding(
                    get: { framing.zoom },
                    set: { zoom in
                        source.setFraming(framing.zoomed(to: zoom), slot: target.slot)
                    }
                ), in: CameraFraming.zoomRange) { editing in
                    if !editing { source.framingEnded(slot: target.slot) }
                }
                .controlSize(.small)
                .accessibilityLabel("Zoom")
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.7))
                // Reset sits with the zoom, since it undoes both the zoom and the point.
                Button("Reset") {
                    source.resetFraming(slot: target.slot)
                    source.framingEnded(slot: target.slot)
                }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 6))
                    .opacity(framing.isCentered ? 0.45 : 1)
                    .disabled(framing.isCentered)
                    .help("Back to the middle, not zoomed")
                    .padding(.leading, 4)
            }
            .frame(height: 22)

            Text(note)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 460)
        .hudBackground(cornerRadius: 14)
        .fixedSize()
    }

    private var note: String {
        // What the framing is for is in the popover's title; the note is only how to do it.
        "Drag to move. Pinch or scroll to zoom."
    }
}

extension RecorderModel: FramingSource {
    var framingPicture: FramingPicture { .live(cameraPreview) }

    /// The chosen slot's camera in each of the format's outputs, laid out automatically, as the
    /// preview shows them.
    func cameraPlacements(in slot: CameraSlot) -> [(output: OutputShape, placement: Placement)] {
        var found: [(OutputShape, Placement)] = []
        for output in format?.outputs ?? [] {
            for placement in previewFrame(in: output).placements where placement.cameraSlot == slot {
                found.append((output, placement))
            }
        }
        return found
    }

    /// The framing a slot shows now: a full-screen camera not framed yet follows Split's.
    func shownFraming(_ slot: CameraSlot) -> CameraFraming {
        framings.framing(for: slot)
    }
}

/// The whole camera frame, mirrored as the preview is, with the slot's crop outlined around the framing
/// point in each output it's in, and the point itself.
struct FramingFrame: View {
    let source: any FramingSource
    let slot: CameraSlot
    let size: CGSize
    @State private var liveMirrored = false

    /// The live camera shows mirrored, as the panel does; a recorded frame shows as recorded.
    private var isMirrored: Bool {
        if case .live = source.framingPicture { return liveMirrored }
        return false
    }

    var body: some View {
        let crops = slotCrops
        let framing = source.shownFraming(slot)
        ZStack(alignment: .topLeading) {
            switch source.framingPicture {
            case .live(let feed):
                CameraPreview(feed: feed, crop: CGRect(x: 0, y: 0, width: 1, height: 1),
                              mirroringChanged: { liveMirrored = $0 })
            case .still(let image):
                if let image {
                    Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                } else {
                    Rectangle().fill(.black)
                }
            }
            Canvas { context, canvas in
                let rects = crops.map { (shown($0.crop, in: canvas), $0) }
                // Dim everything outside the first crop.
                if let first = rects.first {
                    var dim = Path(CGRect(origin: .zero, size: canvas))
                    dim.addPath(path(first.0, roundness: first.1.roundness))
                    context.fill(dim, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                }
                for (index, (rect, crop)) in rects.enumerated() {
                    let style = StrokeStyle(lineWidth: 1.5, dash: index == 0 ? [] : [5, 4])
                    context.stroke(path(rect, roundness: crop.roundness), with: .color(.white), style: style)
                    guard let text = crop.label else { continue }
                    let label = context.resolve(Text(text).font(.system(size: 9.5)).foregroundStyle(.white))
                    let labelSize = label.measure(in: canvas)
                    let origin = index == 0 ? CGPoint(x: rect.minX + 4, y: rect.minY + 4) : CGPoint(x: rect.midX - labelSize.width / 2 - 5, y: rect.maxY - labelSize.height - 8)
                    let box = CGRect(x: origin.x, y: origin.y, width: labelSize.width + 10, height: labelSize.height + 2)
                    context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(.black.opacity(0.6)))
                    context.draw(label, at: CGPoint(x: box.midX, y: box.midY))
                }
                // The framing point.
                let point = shownPoint(framing, in: canvas)
                let dot = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.3)))
                context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 1.5)
            }
            .allowsHitTesting(false)
            FramingSurface(size: size, mirrored: isMirrored, framing: framing,
                           change: { source.setFraming($0, slot: slot) },
                           ended: { source.framingEnded(slot: slot) })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The whole camera frame, with this slot's crop outlined around the framing point")
    }

    private struct SlotCrop {
        /// "Video" or "Short" when the slot is in both outputs.
        let label: String?
        let crop: CGRect
        /// The slot's corner radius as a fraction of its shorter side: a card's own roundness.
        let roundness: Double
    }

    /// The slot's camera crop in each output it's in, from the same layouts the export uses, the widest
    /// first. A slot the format doesn't show is drawn as a square.
    private var slotCrops: [SlotCrop] {
        var crops = source.cameraPlacements(in: slot).map { ($0.output, $0.placement) }
        if crops.isEmpty {
            let framing = source.shownFraming(slot)
            let square = LayoutGeometry.framedCrop(source: source.cameraPictureSize, into: CGSize(width: 1, height: 1), framing: framing)
            return [SlotCrop(label: nil, crop: square, roundness: 0)]
        }
        let labelled = crops.count > 1
        return crops
            .map { SlotCrop(label: labelled ? $0.0.title : nil, crop: $0.1.crop,
                            roundness: $0.1.cameraSlot == .card ? ($0.1.corners.all.max() ?? 0) / max(min($0.1.frame.width, $0.1.frame.height), 1) : 0) }
            .sorted { $0.crop.width / $0.crop.height > $1.crop.width / $1.crop.height }
    }

    private func shown(_ crop: CGRect, in size: CGSize) -> CGRect {
        let x = isMirrored ? 1 - crop.maxX : crop.minX
        return CGRect(x: x * size.width, y: crop.minY * size.height, width: crop.width * size.width, height: crop.height * size.height)
    }

    private func shownPoint(_ framing: CameraFraming, in size: CGSize) -> CGPoint {
        let x = isMirrored ? 1 - framing.centerX : framing.centerX
        return CGPoint(x: x * size.width, y: framing.centerY * size.height)
    }

    /// A slot's outline: a card's with its own roundness, a continuous corner (docs/decisions.md, 89).
    private func path(_ rect: CGRect, roundness: Double) -> Path {
        guard roundness > 0 else { return Path(rect) }
        return Path(roundedRect: rect, cornerRadius: roundness * min(rect.width, rect.height), style: .continuous)
    }
}

/// Takes the framing gestures: drag to move the point and its outlines, scroll or pinch to zoom.
/// Movements are in the mirrored picture shown, and turned into the recorded picture's terms.
private struct FramingSurface: NSViewRepresentable {
    let size: CGSize
    let mirrored: Bool
    let framing: CameraFraming
    let change: (CameraFraming) -> Void
    /// A drag finished, or scrolling or pinching paused.
    var ended: () -> Void = {}

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        update(view)
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        update(view)
    }

    private func update(_ view: SurfaceView) {
        view.size = size
        view.mirrored = mirrored
        view.framing = framing
        view.change = change
        view.ended = ended
    }

    final class SurfaceView: NSView {
        var size = CGSize.zero
        var mirrored = true
        var framing = CameraFraming.centered
        var change: (CameraFraming) -> Void = { _ in }
        var ended: () -> Void = {}
        private var drag = FramingDrag.idle
        private var zoomPause: Timer?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            endDrag()
            drag = .dragging(origin: convert(event.locationInWindow, from: nil), framing: framing, mirrored: mirrored)
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if let framing = drag.framing(at: point, in: size) { change(framing) }
        }

        override func mouseUp(with event: NSEvent) {
            endDrag()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { endDrag() }
            super.viewWillMove(toWindow: newWindow)
        }

        private func endDrag() {
            guard case .dragging = drag else { return }
            drag = .idle
            NSCursor.pop()
            ended()
        }

        override func scrollWheel(with event: NSEvent) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            zoom(by: exp(delta * 0.01))
        }

        override func magnify(with event: NSEvent) {
            zoom(by: 1 + event.magnification)
        }

        private func zoom(by factor: Double) {
            change(framing.zoomed(to: framing.zoom * factor))
            // Scrolling and pinching have no reliable end on every device, so a pause ends them.
            zoomPause?.invalidate()
            zoomPause = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.ended() }
            }
        }
    }
}

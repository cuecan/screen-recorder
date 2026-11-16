import AppKit
import Observation
import ProjectKit
import RecorderKit
import SwiftUI

/// How the floating Recording Panel shows: the preview of the export, the camera alone, or Hidden
/// (docs/decisions.md, 50 and 82).
enum FloatingPanelChoice {
    case preview, camera, hidden

    var title: String {
        switch self {
        case .preview: "Preview"
        case .camera: "Camera only"
        case .hidden: "Hidden"
        }
    }
}

/// The floating Recording Panel (docs/ui.md, R6; docs/decisions.md, 82). While setting up, the setup element
/// shows the preview (docs/decisions.md, 79); from Record the panel is on its own, showing what it showed
/// last on the element's display, at the width it had there for that view, in the place it had there, the
/// preview at Full's width the first time. It resizes from any edge or corner, its picture keeping its
/// shape, and goes wherever the creator drags it, on any display. It never appears in the recording and
/// never brings up the Dock icon.
@Observable
final class RecordingPanelController {
    @ObservationIgnored private unowned let recorder: RecorderModel
    @ObservationIgnored private var panel: OverlayPanel?
    @ObservationIgnored private var moveObserver: (any NSObjectProtocol)?
    /// The panel is being placed by CueCan, not dragged by the creator.
    @ObservationIgnored private var isPlacing = false
    @ObservationIgnored private var isDraggingWindow = false
    /// The creator is dragging an edge: the drag sets the frame, not the content's size.
    @ObservationIgnored private var resizeStart: CGRect?

    private(set) var memory: RecordingPanelMemory {
        didSet {
            if let data = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(data, forKey: "recordingPanel") }
        }
    }
    /// What the panel shows now.
    private(set) var shows = RecordingPanelShows.preview
    /// The panel's width now. The height follows it.
    private(set) var width = RecordingPanelLayout.firstWidth(showing: .preview, destination: nil)
    /// A view picked in the menu bar's menu while setting up, before the panel shows: the take starts in it.
    @ObservationIgnored private var showsForNextTake: RecordingPanelShows?

    init(recorder: RecorderModel) {
        self.recorder = recorder
        let data = UserDefaults.standard.data(forKey: "recordingPanel")
        memory = data.flatMap { try? JSONDecoder().decode(RecordingPanelMemory.self, from: $0) } ?? RecordingPanelMemory()
    }

    var choice: FloatingPanelChoice {
        memory.isHidden ? .hidden : shows == .camera ? .camera : .preview
    }

    var isShowing: Bool { panel?.isVisible ?? false }
    /// The display the floating panel is on, while it shows.
    var screen: NSScreen? { isShowing ? panel?.screen : nil }
    /// Whether the panel is narrow enough to drop its words (docs/ui.md, R6).
    var isNarrow: Bool { RecordingPanelLayout.isNarrow(width: width) }

    /// Shows the floating panel as it last was, or hides it: ⌃⌥⌘P, or the menu bar menu (docs/ui.md, R1).
    func toggleShown() {
        guard recorder.isActive else { return }
        choose(choice == .hidden ? (shows == .camera ? .camera : .preview) : .hidden)
    }

    /// Preview, Camera only or Hidden, from the panel's toggle or the menu bar menu. Camera only needs the
    /// camera on.
    func choose(_ choice: FloatingPanelChoice) {
        switch choice {
        case .hidden:
            memory.isHidden = true
            panel?.orderOut(nil)
            tearDown()
        case .preview, .camera:
            let chosen: RecordingPanelShows = choice == .camera ? .camera : .preview
            guard chosen == .preview || recorder.isCameraOn else { return }
            let wasHidden = memory.isHidden
            memory.isHidden = false
            if let panel {
                guard wasHidden || chosen != shows else { return }
                switchTo(chosen, panel: panel)
            } else if recorder.phase == .settingUp {
                // While setting up there's no panel yet; the take will start in this view.
                showsForNextTake = chosen
                shows = chosen
            } else if recorder.isActive {
                show(showing: chosen)
            }
        }
    }

    /// Shows the panel for a take, on the setup element's display, as it last was there (the preview at
    /// Full's width the first time), fully see-through, for the hand-over to fade in. Nil when the panel is
    /// Hidden (docs/ui.md, R10).
    func showForRecording(on screen: NSScreen?) -> NSWindow? {
        guard !memory.isHidden else { return nil }
        let chosen = showsForNextTake
        showsForNextTake = nil
        show(showing: chosen, on: screen)
        panel?.alphaValue = 0
        return panel
    }

    /// Where the panel's picture is, in screen coordinates: the preview's tiles, or the camera's square.
    var pictureFrame: CGRect? {
        guard let panel else { return nil }
        let picture = RecordingPanelLayout.pictureSize(width: width, showing: shows, destination: recorder.destination)
        let padding = RecordingPanelLayout.padding
        let top = panel.frame.maxY - padding - RecordingPanelLayout.headerHeight - RecordingPanelLayout.spacing
        return CGRect(x: panel.frame.minX + padding, y: top - picture.height, width: picture.width, height: picture.height)
    }

    /// Shows the floating panel, in what it last showed on its display unless a view is given.
    func show(showing chosen: RecordingPanelShows? = nil, on preferred: NSScreen? = nil) {
        guard !memory.isHidden else { return }
        if let panel {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        let screen = preferred ?? memory.lastDisplay.flatMap { id in NSScreen.screens.first { $0.persistentID == id } }
            ?? NSScreen.with(id: recorder.area.selectedDisplayID) ?? NSScreen.underPointer
        let id = screen?.persistentID
        let remembered = memory.shows(on: id, cameraOn: recorder.isCameraOn)
        shows = chosen.flatMap { $0 == .camera && !recorder.isCameraOn ? nil : $0 } ?? remembered
        width = clamped(memory.width(on: id, showing: shows, destination: recorder.destination), on: screen)
        let panel = OverlayPanel.hosting(FloatingPanelContent(recorder: recorder, controller: self), level: .captureControls, takesKeyboard: true)
        panel.isMovableByWindowBackground = true
        panel.title = "Recording Panel"
        panel.onUserDragStarted = { [weak self] in self?.isDraggingWindow = true }
        panel.onUserDragEnded = { [weak self] in
            guard let self else { return }
            self.isDraggingWindow = false
            if let panel = self.panel { self.contentSizeChanged(panel.fittingSize) }
            self.remember()
        }
        if let content = panel.contentView {
            panel.contentView = RecordingPanelContainer(content: content, controller: self)
        }
        self.panel = panel
        place(panel, on: screen)
        panel.orderFrontRegardless()
        remember()
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.resizeStart == nil, !self.isDraggingWindow else { return }
                self.remember()
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        showsForNextTake = nil
        tearDown()
    }

    private func tearDown() {
        TransientPanel.closeCurrent()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel = nil
    }

    /// The other view, at the width it last had on this display, grown or shrunk from the top left
    /// corner. The camera's preview layers stay as they are; only their frames change (docs/ui.md, R6).
    private func switchTo(_ chosen: RecordingPanelShows, panel: OverlayPanel) {
        remember()
        let screen = NSScreen.holding(panel.frame)
        shows = chosen
        width = clamped(memory.width(on: screen?.persistentID, showing: chosen, destination: recorder.destination), on: screen)
        resizeToContent()
        panel.orderFrontRegardless()
        remember()
    }

    /// Where the panel was last on this display, or beside the area, or the display's top right corner.
    private func place(_ panel: OverlayPanel, on screen: NSScreen?) {
        guard let screen else { return }
        isPlacing = true
        defer { isPlacing = false }
        let fitting = panel.fittingSize
        let frame = screen.persistentID.flatMap { id in
            memory.frame(on: id, panelSize: fitting, displayFrame: screen.frame, visible: screen.visibleFrame)
        } ?? ControlPlacement.panel(
            size: fitting,
            area: recorder.area.placement.flatMap { NSScreen.with(id: $0.displayID) == screen ? $0.frame : nil },
            display: screen.visibleFrame
        )
        panel.setFrame(frame, display: true)
    }

    private func resizeToContent() {
        guard let panel else { return }
        isPlacing = true
        defer { isPlacing = false }
        panel.contentView?.layoutSubtreeIfNeeded()
        contentSizeChanged(panel.fittingSize)
    }

    /// The content changed size, such as the toggle or a problem line: keep the top left corner where it is.
    func contentSizeChanged(_ size: CGSize) {
        guard let panel, resizeStart == nil, !isDraggingWindow, size.width > 0, size.height > 0, panel.frame.size != size else { return }
        let top = CGRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        let visible = (NSScreen.holding(panel.frame) ?? NSScreen.main)?.visibleFrame ?? top
        let wasPlacing = isPlacing
        isPlacing = true
        panel.setFrame(AreaGeometry.clamped(top, to: visible), display: true)
        isPlacing = wasPlacing
    }

    // MARK: - Resizing

    /// The panel's rows beyond its usual chrome, such as a problem line, which keep their height as it
    /// resizes.
    private var extraHeight: Double {
        guard let panel else { return 0 }
        let usual = RecordingPanelLayout.size(width: panel.frame.width, showing: shows, destination: recorder.destination).height
        return max(0, panel.frame.height - usual)
    }

    func resizeBegan() {
        resizeStart = panel?.frame
    }

    /// An edge or corner dragged by `translation` (screen points, y up) since the drag began.
    func resize(dragging edges: RecordingPanelResize.Edges, by translation: CGVector) {
        guard let panel, let start = resizeStart else { return }
        let visible = (NSScreen.holding(start) ?? NSScreen.main)?.visibleFrame ?? start
        let extra = max(0, start.height - RecordingPanelLayout.size(width: start.width, showing: shows, destination: recorder.destination).height)
        let frame = RecordingPanelResize.frame(from: start, dragging: edges, by: translation, showing: shows,
                                               destination: recorder.destination, extraHeight: extra, within: visible)
        guard frame != panel.frame else { return }
        width = frame.width
        panel.setFrame(frame, display: true)
    }

    func resizeEnded() {
        resizeStart = nil
        guard let panel else { return }
        // Settle on the content's own height at the new width, from the top left.
        panel.contentView?.layoutSubtreeIfNeeded()
        contentSizeChanged(panel.fittingSize)
        remember()
    }

    /// A width kept between 220 pt and what the display allows.
    private func clamped(_ width: Double, on screen: NSScreen?) -> Double {
        guard let visible = screen?.visibleFrame else { return max(RecordingPanelLayout.minimumWidth, width) }
        return RecordingPanelLayout.clampedWidth(width, showing: shows, destination: recorder.destination,
                                                 within: visible.size, extraHeight: extraHeight)
    }

    private func remember() {
        guard let panel, let screen = NSScreen.holding(panel.frame), let id = screen.persistentID else { return }
        memory.remember(showing: shows, destination: recorder.destination, frame: panel.frame, on: id, displayFrame: screen.frame)
    }
}

/// The floating panel's content, at the panel's width.
private struct FloatingPanelContent: View {
    let recorder: RecorderModel
    let controller: RecordingPanelController

    var body: some View {
        RecordingPanelView(recorder: recorder, shows: controller.shows, width: controller.width, isNarrow: controller.isNarrow)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.contentSizeChanged($0) }
    }
}

/// The panel's edges and corners, which resize it like any window's (docs/ui.md, R6).
///
/// The panel is a borderless, non-activating `NSPanel`, so it tracks its own edges rather than relying on
/// `.resizable`: a 5 pt band along each edge and a 14 pt square at each corner, inside the panel, show
/// `NSCursor.frameResize(position:directions:)` and drag the edge. Everywhere else, clicks go to the panel's
/// content as before.
final class PanelResizeHandles: NSView {
    weak var controller: RecordingPanelController?
    private static let edge: CGFloat = 5
    private static let corner: CGFloat = 14
    private var showsResizeCursor = false

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// The edges under a point in the view, or none away from them.
    func edges(at point: NSPoint) -> RecordingPanelResize.Edges {
        let corner = Self.corner, edge = Self.edge
        var edges: RecordingPanelResize.Edges = []
        let nearLeft = point.x < corner, nearRight = point.x > bounds.width - corner
        let nearBottom = point.y < corner, nearTop = point.y > bounds.height - corner
        if (nearLeft || nearRight) && (nearBottom || nearTop) {
            edges.insert(nearLeft ? .left : .right)
            edges.insert(nearBottom ? .bottom : .top)
            return edges
        }
        if point.x < edge { edges.insert(.left) }
        if point.x > bounds.width - edge { edges.insert(.right) }
        if point.y < edge { edges.insert(.bottom) }
        if point.y > bounds.height - edge { edges.insert(.top) }
        return edges
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) && !edges(at: local).isEmpty ? self : nil
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) {
        if showsResizeCursor { NSCursor.arrow.set() }
        showsResizeCursor = false
    }

    private func updateCursor(at point: NSPoint) {
        let edges = edges(at: point)
        if let cursor = Self.cursor(for: edges) {
            cursor.set()
            showsResizeCursor = true
        } else if showsResizeCursor {
            NSCursor.arrow.set()
            showsResizeCursor = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        let edges = edges(at: convert(event.locationInWindow, from: nil))
        guard !edges.isEmpty, let window, let controller else { return }
        // In screen points, from the pointer itself: the window moves under it when a left or top edge is
        // dragged, so a location in the window would lag.
        let start = NSEvent.mouseLocation
        controller.resizeBegan()
        Self.cursor(for: edges)?.push()
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else { return }
            let now = NSEvent.mouseLocation
            controller.resize(dragging: edges, by: CGVector(dx: now.x - start.x, dy: now.y - start.y))
            if event.type == .leftMouseUp { stop.pointee = true }
        }
        NSCursor.pop()
        controller.resizeEnded()
    }

    static func cursor(for edges: RecordingPanelResize.Edges) -> NSCursor? {
        let position: NSCursor.FrameResizePosition
        switch (edges.contains(.left), edges.contains(.right), edges.contains(.top), edges.contains(.bottom)) {
        case (true, _, true, _): position = .topLeft
        case (true, _, _, true): position = .bottomLeft
        case (_, true, true, _): position = .topRight
        case (_, true, _, true): position = .bottomRight
        case (true, _, _, _): position = .left
        case (_, true, _, _): position = .right
        case (_, _, true, _): position = .top
        case (_, _, _, true): position = .bottom
        default: return nil
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
}

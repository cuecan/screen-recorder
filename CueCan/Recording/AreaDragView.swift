import AppKit
import RecorderKit
import SwiftUI

/// Part of the area's frame that drags: an edge of the outline moves the area, a corner handle resizes it,
/// and the capsule's handle moves it (docs/ui.md, R2). Drags are tracked in desktop coordinates, which stay
/// put while the panel holding this view moves with the area.
final class AreaDragView: NSView {
    enum Role {
        /// One side of the outline. The line is drawn at `line`, in the view's coordinates.
        case edge
        case corner(AreaGeometry.Corner)
        /// The four-way arrows in the capsule.
        case moveHandle
    }

    private weak var controller: CaptureAreaController?
    private let role: Role
    /// Where the outline's line is, in the view's coordinates, and its colour.
    var line: CGRect = .zero { didSet { needsDisplay = true } }
    var lineColor: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var isDraggable = true { didSet { window?.invalidateCursorRects(for: self) } }
    private var startPoint = CGPoint.zero
    private var startFrame = CGRect.zero

    init(controller: CaptureAreaController, role: Role) {
        self.controller = controller
        self.role = role
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        switch role {
        case .edge:
            setAccessibilityLabel("Drag to move the area")
        case .corner:
            setAccessibilityLabel("Drag to resize the area")
            toolTip = "Drag to resize · the shape stays the same"
        case .moveHandle:
            setAccessibilityLabel("Drag to move the area")
            toolTip = "Drag to move the area"
        }
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch role {
        case .edge:
            // A nearly clear fill, so the whole band takes the mouse, not only the line.
            NSColor.black.withAlphaComponent(isDraggable ? 0.01 : 0).setFill()
            bounds.fill()
            lineColor.setFill()
            line.fill()
        case .corner:
            let knob = CGRect(x: bounds.midX - 6, y: bounds.midY - 6, width: 12, height: 12)
            NSColor.black.withAlphaComponent(0.01).setFill()
            bounds.fill()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 3
            shadow.shadowColor = .black.withAlphaComponent(0.5)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
        case .moveHandle:
            NSColor.black.withAlphaComponent(0.01).setFill()
            bounds.fill()
        }
    }

    override func resetCursorRects() {
        guard isDraggable else { return }
        switch role {
        case .edge, .moveHandle:
            addCursorRect(bounds, cursor: .openHand)
        case .corner(let corner):
            let position: NSCursor.FrameResizePosition = switch corner {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            addCursorRect(bounds, cursor: .frameResize(position: position, directions: .all))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isDraggable ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        startFrame = controller?.placement?.frame ?? .zero
        if case .corner = role {} else { NSCursor.closedHand.push() }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let translation = CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y)
        controller?.adjust(from: startFrame, corner: corner, translation: translation)
    }

    override func mouseUp(with event: NSEvent) {
        if case .corner = role {} else { NSCursor.pop() }
        controller?.dragEnded(from: startFrame)
    }

    private var corner: AreaGeometry.Corner? {
        if case .corner(let corner) = role { return corner }
        return nil
    }
}

/// The capsule's move handle, in SwiftUI.
struct AreaMoveHandle: NSViewRepresentable {
    let controller: CaptureAreaController

    func makeNSView(context: Context) -> AreaDragView {
        AreaDragView(controller: controller, role: .moveHandle)
    }

    func updateNSView(_ view: AreaDragView, context: Context) {}
}

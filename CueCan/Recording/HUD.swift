import AppKit
import SwiftUI

/// The dark HUD look of the setup bar and the Recording Panel, which float over any app (docs/ui.md,
/// "Recording"): the system's HUD material, blurred behind the window, with rounded corners.
struct HUDBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    /// Dragging the background moves the window: the setup bar and the Recording Panel.
    var movesWindow = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = movesWindow ? DraggingEffectView() : NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
    }

    /// A stretchable rounded rectangle, so the blur has the shape's corners.
    private static func mask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// The HUD material that moves its window when dragged.
private final class DraggingEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// A clear area that moves its window when dragged, laid over views that take the mouse themselves, such
/// as the camera's preview. AppKit's drag-by-background doesn't reach through SwiftUI's hosting view, so
/// the panels move this way (docs/decisions.md, 50: the panel goes on any display, such as a teleprompter).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window.performDrag(with: event)
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

extension View {
    /// The HUD material behind a view, with a hairline edge, as the bar and the panel use.
    func hudBackground(cornerRadius: CGFloat, movesWindow: Bool = false) -> some View {
        background(HUDBackground(cornerRadius: cornerRadius, movesWindow: movesWindow))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

/// Recording red, kept for recording and Stop (docs/ui.md, "Recording"). The system's red.
extension Color {
    static let recordingRed = Color(nsColor: .systemRed)
}

/// A dashed tile standing in for a source that's off, so the layout keeps its shape (docs/ui.md, R6).
struct OffTile: View {
    let title: String
    let systemImage: String
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.white.opacity(0.2))
            .background(.white.opacity(0.03), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
    }
}

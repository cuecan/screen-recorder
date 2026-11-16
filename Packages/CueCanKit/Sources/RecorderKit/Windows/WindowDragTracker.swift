import CoreGraphics
import Foundation

/// Notices another app's window being dragged over the capture area and released there
/// (docs/decisions.md, 21), from what can be seen of a drag from outside the app: where the pointer is,
/// and where the window it went down on is now.
///
/// A window counts as dragged once it has moved without changing size, so resizing a window by its edge
/// or selecting text in it never snaps it. Whether it's over the area goes by the pointer, which is what the
/// creator is aiming with.
public struct WindowDragTracker: Sendable {
    /// What the drag means for the area.
    public enum Change: Sendable, Equatable {
        /// A dragged window came over the area: light it up.
        case entered(SnappableWindow)
        /// It left the area, or the drag ended outside it.
        case left
        /// It was released over the area: snap it in. `from` is where it was before the drag, where it
        /// goes back if it can't fit.
        case dropped(SnappableWindow, from: CGRect)
    }

    /// How far a window has to move, in points, to count as dragged.
    public static let threshold: Double = 3

    /// The capture area, in AppKit's global coordinates. Nil while no format is chosen.
    public var area: CGRect?
    private struct Press: Sendable {
        var window: SnappableWindow
        let start: CGRect
    }

    /// A press becomes a drag only while the window keeps its size. Once it disappears or resizes,
    /// the gesture is rejected until the next press, even if it later returns to its original size.
    private enum State: Sendable {
        case idle
        case pressed(Press)
        case dragging(Press, isOver: Bool)
        case rejected
    }

    private var state = State.idle

    public init(area: CGRect? = nil) {
        self.area = area
    }

    /// Whether a press is still eligible to become a drop.
    public var isTracking: Bool {
        switch state {
        case .pressed, .dragging: true
        case .idle, .rejected: false
        }
    }

    /// The mouse went down on a window (or on nothing of another app's).
    public mutating func pressed(on window: SnappableWindow?) {
        state = window.map { .pressed(Press(window: $0, start: $0.frame)) } ?? .idle
    }

    /// Stops following a gesture, returning the change needed to remove its highlight.
    public mutating func cancel() -> Change? {
        defer { state = .idle }
        if case .dragging(_, isOver: true) = state { return .left }
        return nil
    }

    /// A look at the pointer and the pressed window's frame during the press.
    public mutating func sampled(pointer: CGPoint, windowFrame: CGRect?) -> Change? {
        var press: Press
        let wasOver: Bool
        let wasDragging: Bool
        switch state {
        case .pressed(let value):
            press = value
            wasOver = false
            wasDragging = false
        case .dragging(let value, let isOver):
            press = value
            wasOver = isOver
            wasDragging = true
        case .idle, .rejected:
            return nil
        }
        guard let windowFrame,
              abs(windowFrame.width - press.start.width) <= 1,
              abs(windowFrame.height - press.start.height) <= 1 else {
            state = .rejected
            return wasOver ? .left : nil
        }
        let moved = hypot(windowFrame.minX - press.start.minX, windowFrame.minY - press.start.minY)
        guard wasDragging || moved >= Self.threshold else { return nil }
        press.window.frame = windowFrame
        let over = area?.contains(pointer) ?? false
        state = .dragging(press, isOver: over)
        if over, !wasOver { return .entered(press.window) }
        if !over, wasOver { return .left }
        return nil
    }

    /// The mouse came up. The final sample must still describe a movable window.
    public mutating func released(pointer: CGPoint, windowFrame: CGRect?) -> Change? {
        defer { state = .idle }
        let change = sampled(pointer: pointer, windowFrame: windowFrame)
        if case .dragging(let press, isOver: true) = state {
            return .dropped(press.window, from: press.start)
        }
        return change == .left ? .left : nil
    }
}

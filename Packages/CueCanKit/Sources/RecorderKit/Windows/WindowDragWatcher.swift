import AppKit
import Foundation

/// Watches for another app's window being dragged onto the capture area (docs/decisions.md, 21).
///
/// It needs no Accessibility access: a global monitor sees the mouse go down on another app's window, and
/// while the button is held the window's frame is read from the window server about 30 times a second.
/// Polling, rather than following drag events, because the window server drags most title bars itself
/// and other apps' drag events may never reach a monitor. ``WindowDragTracker`` decides what it means.
@MainActor
public final class WindowDragWatcher {
    /// Called when a dragged window comes over the area, leaves it, or is released over it.
    public var onChange: ((WindowDragTracker.Change) -> Void)?
    /// The area to watch, in AppKit's global coordinates. Nil while no format is chosen.
    public var area: CGRect? {
        get { tracker.area }
        set {
            tracker.area = newValue
            if newValue == nil { endPress() }
        }
    }

    private var tracker = WindowDragTracker()
    private var monitor: Any?
    private var timer: Timer?
    private var pressedWindow: CGWindowID?

    /// How often the pressed window is looked at during a press.
    public static let pollInterval: TimeInterval = 1.0 / 30

    public init() {}

    public var isWatching: Bool { monitor != nil }

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseWentDown() }
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        endPress()
    }

    private func mouseWentDown() {
        endPress()
        guard tracker.area != nil else { return }
        let window = WindowSnapper.window(at: NSEvent.mouseLocation)
        tracker.pressed(on: window)
        pressedWindow = window?.id
        guard window != nil else { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // Common modes, so it keeps running while a menu or a drag holds the run loop.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard let id = pressedWindow else { return endPress() }
        let frame = WindowSnapper.frame(ofWindow: id)
        let pointer = NSEvent.mouseLocation
        if NSEvent.pressedMouseButtons & 1 == 0 {
            let change = tracker.released(pointer: pointer, windowFrame: frame)
            endPress()
            if let change { onChange?(change) }
        } else if let change = tracker.sampled(pointer: pointer, windowFrame: frame) {
            onChange?(change)
        }
    }

    private func endPress() {
        timer?.invalidate()
        timer = nil
        pressedWindow = nil
        if let change = tracker.cancel() { onChange?(change) }
    }
}

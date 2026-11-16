import AppKit
import Observation

/// A temporary HUD or popover and the event monitors that exist only while it is open.
/// Only one is open at a time. Setup's keyboard handler yields to it, so Esc dismisses the
/// popover without also changing the recording's format.
@Observable
final class TransientPanel {
    private struct Presentation {
        let panel: OverlayPanel
        let monitors: [Any]
    }

    private enum State {
        case closed
        case open(Presentation)
    }

    private var state = State.closed
    private static weak var current: TransientPanel?

    var isOpen: Bool {
        if case .open = state { return true }
        return false
    }

    /// Used before setup handles Return or Esc. The popover owns its keyboard events.
    static func owns(_ window: NSWindow?) -> Bool {
        guard case .open(let presentation) = current?.state else { return false }
        return window === presentation.panel
    }

    static func closeCurrent() {
        current?.close()
    }

    func open(_ panel: OverlayPanel, frame: CGRect) {
        Self.closeCurrent()
        close()
        var monitors: [Any] = []
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, case .open(let presentation) = self.state else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                self.close()
                return nil
            }
            if event.window !== presentation.panel { self.close() }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(global) }
        state = .open(Presentation(panel: panel, monitors: monitors))
        Self.current = self
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard case .open(let presentation) = state else { return }
        state = .closed
        if Self.current === self { Self.current = nil }
        for monitor in presentation.monitors { NSEvent.removeMonitor(monitor) }
        presentation.panel.orderOut(nil)
    }
}

import AppKit
import SwiftUI

/// The system colour panel, for a background colour of your own. One for the app, since the panel is; each
/// opening says where its colour goes. It reports when you let go, not on every step of a drag, so a choice is
/// one change in History.
@MainActor
final class BackgroundColorPanel: NSObject, NSWindowDelegate {
    static let shared = BackgroundColorPanel()
    private var onChoose: ((String) -> Void)?

    func open(_ hex: String, onChoose: @escaping (String) -> Void) {
        self.onChoose = onChoose
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.delegate = self
        panel.color = NSColor(Color(hex: hex))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Stop targeting a project/output as soon as its Look inspector leaves the screen.
    func close() {
        onChoose = nil
        NSColorPanel.shared.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onChoose = nil
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        if let hex = Color(nsColor: panel.color).hex { onChoose?(hex) }
    }
}

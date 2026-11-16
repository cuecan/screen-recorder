import AppKit
import SwiftUI

/// An overlay panel whose SwiftUI content is set directly, so its size is known at once when it's placed.
final class HostedPanel {
    let panel: OverlayPanel
    private let hosting: NSHostingView<AnyView>

    init(level: NSWindow.Level, passesClicksThrough: Bool, takesKeyboard: Bool = false) {
        panel = OverlayPanel(frame: .zero, level: level, passesClicksThrough: passesClicksThrough)
        panel.takesKeyboard = takesKeyboard
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
    }

    /// Shows a view, and returns the size it wants.
    @discardableResult
    func set(_ view: some View) -> CGSize {
        hosting.rootView = AnyView(view.environment(\.colorScheme, .dark))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    /// Puts the panel on screen at a frame.
    func show(at frame: CGRect) {
        panel.setFrame(frame.integral, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }
}

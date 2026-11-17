import AppKit
import SwiftUI

/// A borderless panel over other apps' windows, on every Space, that never appears in a recording and
/// never activates CueCan, so it never brings up the Dock icon (docs/decisions.md, 29).
final class OverlayPanel: NSPanel {
    /// Whether the panel takes keyboard focus when clicked, for Esc and Return (docs/decisions.md, 49).
    var takesKeyboard = false
    /// Window-wide drag hooks, shared by the title, preview and HUD background. Owners defer their
    /// display-dependent layout and position persistence until AppKit finishes the drag.
    var onUserDragStarted: (() -> Void)?
    var onUserDragEnded: (() -> Void)?
    private lazy var dragMonitor = WindowDragMonitor(
        began: { [weak self] in self?.onUserDragStarted?() },
        ended: { [weak self] in self?.onUserDragEnded?() })

    init(frame: CGRect, level: NSWindow.Level, passesClicksThrough: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = passesClicksThrough
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // The capture leaves CueCan out with its display filter; this keeps the panels out of other apps'
        // captures and screenshots too.
        sharingType = Self.isVisibleToScreenshots ? .readOnly : .none
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .darkAqua)
    }

    /// Debug builds only: the `VisibleToScreenshots` default lets screenshot tools see the panels, for
    /// checking the UI by eye. Launch with `-VisibleToScreenshots YES`, or set it from the debugger
    /// (the `cuecan-run-app` skill). The recording leaves CueCan out with its display
    /// filter either way.
    static var isVisibleToScreenshots: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "VisibleToScreenshots")
        #else
        false
        #endif
    }

    override var canBecomeKey: Bool { takesKeyboard || !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }

    /// AppKit moves a window down until it is clear of the menu bar. The dimming covers the menu bar on
    /// purpose, and moved down it covered the top of the capture area by the menu bar's height. Every
    /// overlay panel is placed exactly by its owner, which keeps the ones a person uses on the desktop.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func performDrag(with event: NSEvent) {
        dragMonitor.start()
        super.performDrag(with: event)
    }

    override func orderOut(_ sender: Any?) {
        dragMonitor.cancel()
        super.orderOut(sender)
    }

    /// A panel showing a SwiftUI view, sized to it.
    static func hosting(_ view: some View, level: NSWindow.Level, takesKeyboard: Bool = false) -> OverlayPanel {
        let panel = OverlayPanel(frame: CGRect(x: 0, y: 0, width: 10, height: 10), level: level, passesClicksThrough: false)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        // The panel's owner sizes it, from the content's fitting size, so it can keep whichever edge it
        // wants in place; the hosting view resizing the window itself would keep the top edge.
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.takesKeyboard = takesKeyboard
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    /// A SwiftUI view that only shows: clicks pass through it to the window underneath.
    static func label(_ view: some View, level: NSWindow.Level) -> OverlayPanel {
        let panel = hosting(view, level: level)
        panel.ignoresMouseEvents = true
        return panel
    }

    /// A plain colored panel that clicks pass through.
    static func filled(_ color: NSColor, level: NSWindow.Level) -> OverlayPanel {
        let panel = OverlayPanel(frame: .zero, level: level, passesClicksThrough: true)
        panel.backgroundColor = color
        return panel
    }

    /// The SwiftUI content's own size.
    var fittingSize: CGSize {
        contentView?.layoutSubtreeIfNeeded()
        return contentView?.fittingSize ?? frame.size
    }

    /// Resizes to the content, keeping the top left corner where it is.
    func fitContent() {
        let size = fittingSize
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}

extension NSWindow.Level {
    /// The dimming and the area's outline: above other apps' windows.
    static let captureDimming = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    /// The area's controls, the setup bar and the Recording Panel: above the dimming.
    static let captureControls = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// A display id that stays the same across restarts, for remembering where the panel was.
    var persistentID: String? {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// The screen the pointer is on.
    static var underPointer: NSScreen? {
        let point = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }

    /// The screen holding most of a frame.
    static func holding(_ frame: CGRect) -> NSScreen? {
        screens.max { lhs, rhs in
            let a = lhs.frame.intersection(frame), b = rhs.frame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? main
    }

    static func with(id: CGDirectDisplayID?) -> NSScreen? {
        screens.first { $0.displayID == id }
    }
}

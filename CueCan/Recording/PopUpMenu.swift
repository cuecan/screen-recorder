import AppKit
import RecorderKit
import SwiftUI

/// One entry in a pop-up menu.
enum MenuEntry {
    case item(_ title: String, systemImage: String? = nil, checked: Bool = false, enabled: Bool = true,
              destructive: Bool = false, action: @MainActor () -> Void)
    case separator
}

/// Where a pop-up menu opens beside the view it belongs to.
enum MenuEdge {
    case below, above, trailing
}

/// A real `NSMenu` opened from a SwiftUI view with a custom label. SwiftUI's `Menu` flattens its label to
/// a title and an icon on macOS, which can't draw the bar's pickers (docs/ui.md, R2). Being a real menu,
/// clicking away or pressing Esc closes it and nothing happens (docs/decisions.md, 51).
@MainActor
final class MenuAnchor {
    private weak var view: NSView?
    private static weak var presentingAnchor: MenuAnchor?
    private var requestID: UUID?
    private let presentMenu: @MainActor (NSMenu, CGPoint, NSView) -> Void
    /// The menu last opened, kept until the next one: a chosen item's action can arrive after `popUp`
    /// returns, and a menu released by then takes the item and its action with it.
    private var menu: NSMenu?

    init(present: @escaping @MainActor (NSMenu, CGPoint, NSView) -> Void = { menu, point, view in
        menu.popUp(positioning: nil, at: point, in: view)
    }) {
        presentMenu = present
    }

    func attach(to view: NSView) {
        self.view = view
    }

    func detach(from view: NSView) {
        guard self.view === view else { return }
        self.view = nil
        requestID = nil
        menu?.cancelTrackingWithoutAnimation()
        if Self.presentingAnchor === self { Self.presentingAnchor = nil }
    }

    func open(_ entries: [MenuEntry], edge: MenuEdge = .below) {
        guard !entries.isEmpty, view?.window?.isVisible == true,
              Self.presentingAnchor == nil else { return }
        let requestID = UUID()
        self.requestID = requestID
        Self.presentingAnchor = self
        // Finish delivering the SwiftUI/AX button action before creating AppKit's menu window.
        // Use the run loop, not a main-queue block: popUp runs a nested tracking loop, during which
        // main-queue work (including the recorder's state updates) must remain serviceable.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.requestID == requestID else { return }
                defer {
                    if self.requestID == requestID { self.requestID = nil }
                    if Self.presentingAnchor === self { Self.presentingAnchor = nil }
                }
                guard let view = self.view, view.window?.isVisible == true,
                      !view.bounds.isEmpty else { return }
                self.present(entries, edge: edge, in: view)
            }
        }
    }

    private func present(_ entries: [MenuEntry], edge: MenuEdge, in view: NSView) {
        let menu = NSMenu()
        self.menu = menu
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .item(let title, let systemImage, let checked, let enabled, let destructive, let action):
                let item = ClosureMenuItem(title: title, action: action)
                item.state = checked ? .on : .off
                item.isEnabled = enabled
                if let systemImage {
                    let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                    if destructive {
                        item.image = image?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
                    } else {
                        item.image = image
                    }
                }
                if destructive {
                    item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)])
                }
                menu.addItem(item)
            }
        }
        menu.appearance = NSAppearance(named: .darkAqua)
        let bounds = view.bounds
        let point: CGPoint = switch edge {
        case .below: CGPoint(x: bounds.minX, y: view.isFlipped ? bounds.maxY + 4 : bounds.minY - 4)
        case .above: CGPoint(x: bounds.minX, y: view.isFlipped ? bounds.minY - 4 - menu.size.height : bounds.maxY + 4 + menu.size.height)
        case .trailing: CGPoint(x: bounds.maxX + 6, y: view.isFlipped ? bounds.minY : bounds.maxY)
        }
        presentMenu(menu, point, view)
    }

    /// Opens a dark HUD menu, as the Recording Panel's Discard menu is drawn (docs/ui/mockups/RecMonitor.dc.html):
    /// 168 pt wide, a row of 30 pt per item with its icon. It acts like a menu: clicking away or Esc closes
    /// it and nothing happens.
    func openHUD(_ entries: [MenuEntry], edge: MenuEdge) {
        guard let view, let window = view.window else { return }
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        HUDMenu.shared.open(entries, beside: anchor, edge: edge)
    }
}

/// The HUD menu's panel: one at a time, closed by a choice, a click anywhere else, or Esc.
@MainActor
private final class HUDMenu {
    static let shared = HUDMenu()
    private let presentation = TransientPanel()

    func open(_ entries: [MenuEntry], beside anchor: CGRect, edge: MenuEdge) {
        close()
        let rows: [HUDMenuView.Row] = entries.compactMap { entry in
            guard case .item(let title, let systemImage, _, let enabled, let destructive, let action) = entry, enabled else { return nil }
            return HUDMenuView.Row(title: title, systemImage: systemImage, destructive: destructive) { [weak self] in
                self?.close()
                action()
            }
        }
        let panel = OverlayPanel.hosting(HUDMenuView(rows: rows), level: .popUpMenu, takesKeyboard: true)
        panel.hasShadow = true
        let size = panel.fittingSize
        let origin: CGPoint = switch edge {
        case .above: CGPoint(x: anchor.minX, y: anchor.maxY + 6)
        case .below: CGPoint(x: anchor.minX, y: anchor.minY - 6 - size.height)
        case .trailing: CGPoint(x: anchor.maxX + 8, y: anchor.minY)
        }
        var frame = CGRect(origin: origin, size: size)
        if let visible = NSScreen.holding(anchor)?.visibleFrame { frame = AreaGeometry.clamped(frame, to: visible) }
        presentation.open(panel, frame: frame)
    }

    func close() {
        presentation.close()
    }
}

/// The HUD menu's rows.
private struct HUDMenuView: View {
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String?
        let destructive: Bool
        let action: () -> Void
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                HUDMenuRow(row: row)
            }
        }
        .padding(6)
        .frame(width: 168)
        .hudBackground(cornerRadius: 12)
        .fixedSize()
    }
}

private struct HUDMenuRow: View {
    let row: HUDMenuView.Row
    @State private var isHovered = false

    var body: some View {
        Button(action: row.action) {
            HStack(spacing: 8) {
                if let systemImage = row.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16)
                }
                Text(row.title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(row.destructive ? Color(nsColor: .systemRed) : .white)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isHovered ? .white.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A menu item that runs a closure.
nonisolated final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", action: @escaping @MainActor () -> Void) {
        run = action
        super.init(title: title, action: #selector(runAction), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        run = {}
        super.init(coder: coder)
    }

    @MainActor @objc private func runAction() { run() }
}

/// Puts a ``MenuAnchor`` on the view it's the background of.
struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeCoordinator() -> MenuAnchor { anchor }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.attach(to: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: MenuAnchor) {
        coordinator.detach(from: view)
    }
}

/// A button with any label that opens a pop-up menu.
struct PopUpMenuButton<Label: View>: View {
    var edge: MenuEdge = .below
    let entries: () -> [MenuEntry]
    @ViewBuilder let label: () -> Label
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            // No entries, no menu: a greyed-out picker still shows its reason on hover.
            let entries = entries()
            if !entries.isEmpty { anchor.open(entries, edge: edge) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
    }
}


import AppKit
import SwiftUI

/// Attach the editor's shortcuts when AppKit actually attaches its view to a window. A deferred read
/// during SwiftUI construction can run before that happens and leave the editor without a key monitor.
struct EditorKeyboardMonitor: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> KeyboardView { KeyboardView(model: model) }
    func updateNSView(_ view: KeyboardView, context: Context) {}
    static func dismantleNSView(_ view: KeyboardView, coordinator: ()) { view.keys.stop() }

    final class KeyboardView: NSView {
        let keys = EditorKeys()
        private let model: EditorModel

        init(model: EditorModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            keys.start(model: model, in: window)
        }
    }
}

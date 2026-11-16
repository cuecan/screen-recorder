import AppKit
import SwiftUI

/// A native checkbox representing an entire selection. A mixed value commits one operation for all
/// selected clips, rather than one write for every individual binding.
struct InspectorToggle: NSViewRepresentable {
    let title: String
    let value: Bool?
    let set: (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        button.allowsMixedState = true
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.set = set
        context.coordinator.value = value
        button.title = title
        button.isEnabled = context.environment.isEnabled
        button.state = value.map { $0 ? .on : .off } ?? .mixed
        button.setAccessibilityLabel(title)
    }

    func makeCoordinator() -> Coordinator { Coordinator(set: set) }

    final class Coordinator: NSObject {
        var set: (Bool) -> Void
        var value: Bool?
        init(set: @escaping (Bool) -> Void) { self.set = set }
        @objc func changed(_ button: NSButton) {
            let changed = value != true
            button.state = changed ? .on : .off
            set(changed)
        }
    }
}

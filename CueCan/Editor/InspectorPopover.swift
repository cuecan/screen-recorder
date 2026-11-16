import SwiftUI

/// The editor presents one transient inspector at a time. Escape dismisses it before changing selection.
enum InspectorPopover: Equatable {
    /// A tool strip audio switch's settings.
    case noiseReduction, equalizer
    case layout
}

extension EditorModel {
    func presentation(of popover: InspectorPopover) -> Binding<Bool> {
        Binding(get: { self.inspectorPopover == popover }, set: { presented in
            if presented { self.inspectorPopover = popover }
            else if self.inspectorPopover == popover { self.inspectorPopover = nil }
        })
    }
}

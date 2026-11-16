import SwiftUI

/// The inspector can be widened for long values without stealing the timeline's width. This is window
/// layout, not an edit; double-click restores the comfortable default.
struct InspectorResizeDivider: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Rectangle().fill(.separator)
            .frame(width: 1)
            .frame(width: 5)
            .contentShape(.rect)
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { drag in
                    if start == nil { start = width }
                    width = min(460, max(280, (start ?? width) - drag.translation.width))
                }
                .onEnded { _ in start = nil })
            .onTapGesture(count: 2) { width = 320 }
            .accessibilityElement()
            .accessibilityLabel("Inspector width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(460, width + 20)
                case .decrement: width = max(280, width - 20)
                @unknown default: break
                }
            }
            .help("Drag to resize. Double-click to reset.")
    }
}

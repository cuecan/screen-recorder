import ProjectKit
import SwiftUI

/// The slider and editable value use the same units and save one change at the end of an adjustment.
struct InspectorSlider: View {
    let title: String
    let value: Double?
    let range: ClosedRange<Double>
    var unit = ""
    var step = 1.0
    var fractionDigits = 0
    var preview: ((Double) -> Void)? = nil
    var cancelPreview: (() -> Void)? = nil
    let set: (Double) -> Void
    @State private var pending = 0.0
    @State private var isEditing = false
    @State private var startingValue = 0.0
    /// Whether this drag has shown any value but the one it started on.
    @State private var leftStart = false

    var body: some View {
        InspectorRow(title) {
            HStack(spacing: 5) {
                Slider(value: $pending, in: range) { editing in
                    isEditing = editing
                    if editing {
                        startingValue = value ?? min(range.upperBound, max(range.lowerBound, 0))
                        leftStart = false
                    } else if let changed = NumericAdjustment.valueToCommit(pending, startingAt: startingValue, fractionDigits: fractionDigits,
                                                                            leftPlaceholder: value == nil && leftStart) {
                        set(changed)
                    } else {
                        pending = value ?? startingValue
                        cancelPreview?()
                    }
                }
                .frame(minWidth: 40, maxWidth: .infinity)
                .accessibilityLabel(title)
                .accessibilityValue(value == nil && !isEditing ? "Mixed" : "\(pending.formatted()) \(unit)")
                .opacity(value == nil && !isEditing ? 0.45 : 1)
                InspectorNumberField(title: title, value: isEditing ? pending : value,
                                     range: range, step: step, fractionDigits: fractionDigits,
                                     preview: preview, cancelPreview: cancelPreview, set: set)
                    .frame(width: 46, height: 22)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary).font(.caption)
                        .frame(width: 18, alignment: .leading)
                }
            }
        }
        .onChange(of: value, initial: true) { _, value in
            if !isEditing { pending = value ?? min(range.upperBound, max(range.lowerBound, 0)) }
        }
        .onChange(of: pending) { _, value in
            guard isEditing else { return }
            if NumericAdjustment.valueToCommit(value, startingAt: startingValue, fractionDigits: fractionDigits) != nil { leftStart = true }
            preview?(value)
        }
    }
}

import AppKit
import SwiftUI

/// Offline audio processing starts on a deliberate choice, never as a pointer scrubs past values.
/// An amount set by an agent remains visible until the creator chooses one of the offered amounts.
struct AudioAmountButtons: View {
    let title: String
    let value: Double
    var showsTitle = true
    /// Saves the amount, and says whether it was saved.
    let set: (Double) -> Bool
    private static let amounts: [Double] = [25, 50, 75, 100]

    var body: some View {
        if showsTitle {
            InspectorRow("Amount") { choices }
        } else {
            choices
        }
    }

    private var choices: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if !Self.amounts.contains(value) {
                Text("\(value.formatted(.number.precision(.fractionLength(0...1))))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            AudioAmountPicker(title: title, value: value, amounts: Self.amounts, set: set)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
    }
}

/// Native segments distribute their labels inside the offered width rather than imposing the
/// SwiftUI picker's intrinsic width on the inspector's shared control column.
private struct AudioAmountPicker: NSViewRepresentable {
    let title: String
    let value: Double
    let amounts: [Double]
    let set: (Double) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: amounts.map { "\(Int($0))%" }, trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.segmentDistribution = .fillProportionally
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = amounts.firstIndex(of: value) ?? -1
        control.isEnabled = context.environment.isEnabled
        control.setAccessibilityLabel(title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? intrinsic.width
        return CGSize(width: width, height: intrinsic.height)
    }

    final class Coordinator: NSObject {
        var parent: AudioAmountPicker
        init(parent: AudioAmountPicker) { self.parent = parent }
        @objc func changed(_ control: NSSegmentedControl) {
            guard control.isEnabled, parent.amounts.indices.contains(control.selectedSegment) else { return }
            let amount = parent.amounts[control.selectedSegment]
            // The control has already moved to the clicked segment. If the amount couldn't be saved,
            // nothing else will move it back: the value it's drawn from hasn't changed.
            if amount != parent.value, !parent.set(amount) {
                control.selectedSegment = parent.amounts.firstIndex(of: parent.value) ?? -1
            }
        }
    }
}

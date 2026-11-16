import AppKit
import ProjectKit
import SwiftUI

/// A typed or horizontally scrubbed number. A drag and a text edit each commit once, so Undo remains
/// useful. Option scrubs precisely and Shift takes larger steps, following professional Mac inspectors.
struct InspectorNumberField: NSViewRepresentable {
    let title: String
    let value: Double?
    var range: ClosedRange<Double>
    var step: Double = 1
    var fractionDigits = 0
    var preview: ((Double) -> Void)? = nil
    var cancelPreview: (() -> Void)? = nil
    let set: (Double) -> Void

    func makeNSView(context: Context) -> NumberField {
        let field = NumberField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.focusRingType = .exterior
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NumberField, context: Context) {
        context.coordinator.parent = self
        field.range = range
        field.isEnabled = context.environment.isEnabled
        field.step = step
        field.fractionDigits = fractionDigits
        field.commit = set
        field.preview = preview
        field.cancelPreview = cancelPreview
        field.placeholderString = "Mixed"
        field.toolTip = "\(title): type, or drag left or right"
        field.setAccessibilityLabel(title)
        if field.currentEditor() == nil, !field.isScrubbing {
            field.number = value
            field.stringValue = value.map { field.formatted($0) } ?? ""
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InspectorNumberField
        private var isCancelling = false
        init(parent: InspectorNumberField) { self.parent = parent }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NumberField else { return }
            guard !isCancelling else {
                field.stringValue = parent.value.map { field.formatted($0) } ?? ""
                return
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let value = formatter.number(from: field.stringValue)?.doubleValue, value.isFinite {
                let clamped = min(parent.range.upperBound, max(parent.range.lowerBound, value))
                if clamped != parent.value { parent.set(clamped) }
                field.number = clamped
                field.stringValue = field.formatted(clamped)
            } else {
                field.stringValue = parent.value.map { field.formatted($0) } ?? ""
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let field = control as? NumberField else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                field.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                isCancelling = true
                field.window?.makeFirstResponder(nil)
                field.stringValue = parent.value.map { field.formatted($0) } ?? ""
                isCancelling = false
                return true
            }
            return false
        }
    }

    final class NumberField: NSTextField {
        var number: Double?
        var range: ClosedRange<Double> = 0...100
        var step = 1.0
        var fractionDigits = 0
        var commit: ((Double) -> Void)?
        var preview: ((Double) -> Void)?
        var cancelPreview: (() -> Void)?
        var isScrubbing = false

        func formatted(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(fractionDigits)))
        }

        override func resetCursorRects() {
            if currentEditor() == nil { addCursorRect(bounds, cursor: .resizeLeftRight) }
            else { super.resetCursorRects() }
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            guard event.clickCount == 1, currentEditor() == nil, let window else {
                super.mouseDown(with: event)
                return
            }
            let origin = event.locationInWindow.x
            let original = number
            let start = number ?? min(range.upperBound, max(range.lowerBound, 0))
            var value = start
            var moved = false
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let delta = next.locationInWindow.x - origin
                guard abs(delta) >= 2 || isScrubbing else { continue }
                isScrubbing = true
                let fine = next.modifierFlags.contains(.option) ? 0.1 : next.modifierFlags.contains(.shift) ? 10.0 : 1.0
                let changed = start + Double(delta) * step * fine
                let quantum = pow(10, -Double(fractionDigits))
                value = min(range.upperBound, max(range.lowerBound, (changed / quantum).rounded() * quantum))
                stringValue = formatted(value)
                if value != start { moved = true }
                preview?(value)
            }
            if isScrubbing {
                finishScrub(at: value, startingAt: start, original: original, moved: moved)
            } else {
                window.makeFirstResponder(self)
                selectText(nil)
            }
        }

        /// Completion is separate from choosing a value: a mixed scrub that never showed another number
        /// stays mixed, and one that came back to its placeholder chooses it.
        ///
        /// - Parameter moved: Whether the scrub showed any value but its start.
        func finishScrub(at value: Double, startingAt start: Double, original: Double?, moved: Bool = false) {
            isScrubbing = false
            if let changed = NumericAdjustment.valueToCommit(value, startingAt: start, fractionDigits: fractionDigits,
                                                             leftPlaceholder: original == nil && moved) {
                number = changed
                stringValue = formatted(changed)
                commit?(changed)
            } else {
                number = original
                stringValue = original.map(formatted) ?? ""
                cancelPreview?()
            }
        }
    }
}

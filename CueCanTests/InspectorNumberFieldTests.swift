import AppKit
import Testing
@testable import CueCan

@MainActor
struct InspectorNumberFieldTests {
    @Test func aMixedScrubThatLeavesItsPlaceholderAndComesBackChoosesIt() {
        let field = InspectorNumberField.NumberField()
        var committed: [Double] = []
        var cancelled = 0
        field.number = nil
        field.commit = { committed.append($0) }
        field.cancelPreview = { cancelled += 1 }
        field.finishScrub(at: 100, startingAt: 100, original: nil, moved: true)
        #expect(committed == [100] && cancelled == 0)
        #expect(field.number == 100)
    }

    @Test func aScrubOfOneValueBackToItsStartIsStillNoChange() {
        let field = InspectorNumberField.NumberField()
        var committed: [Double] = []
        var cancelled = 0
        field.commit = { committed.append($0) }
        field.cancelPreview = { cancelled += 1 }
        field.finishScrub(at: 120, startingAt: 120, original: 120, moved: true)
        #expect(committed.isEmpty && cancelled == 1)
        #expect(field.number == 120)
    }

    @Test func aMixedScrubThatNeverLeavesItsStartStaysMixedWithoutCommitting() {
        let field = InspectorNumberField.NumberField()
        var committed: [Double] = []
        var cancelled = 0
        field.number = nil
        field.stringValue = "80"
        field.commit = { committed.append($0) }
        field.cancelPreview = { cancelled += 1 }
        field.finishScrub(at: 0, startingAt: 0, original: nil)
        #expect(field.number == nil && field.stringValue.isEmpty)
        #expect(committed.isEmpty && cancelled == 1)
    }

    @Test func anUnchangedScrubPreservesTheOriginalPrecision() {
        let field = InspectorNumberField.NumberField()
        field.fractionDigits = 1
        var committed = false
        var cancelled = false
        field.commit = { _ in committed = true }
        field.cancelPreview = { cancelled = true }
        field.finishScrub(at: 44, startingAt: 44.046, original: 44.046)
        #expect(field.number == 44.046)
        #expect(field.stringValue == field.formatted(44.046))
        #expect(cancelled && !committed)
    }

    @Test func aChangedMixedScrubCommitsOnce() {
        let field = InspectorNumberField.NumberField()
        var committed: [Double] = []
        var cancelled = false
        field.commit = { committed.append($0) }
        field.cancelPreview = { cancelled = true }
        field.finishScrub(at: 170, startingAt: 100, original: nil)
        #expect(committed == [170] && !cancelled)
        #expect(field.number == 170)
    }

    @Test func typingThePlaceholderValueIntoAMixedFieldStillChoosesIt() {
        var committed: [Double] = []
        let parent = InspectorNumberField(title: "Center", value: nil, range: 0...100) { committed.append($0) }
        let coordinator = InspectorNumberField.Coordinator(parent: parent)
        let field = InspectorNumberField.NumberField()
        field.stringValue = "0"
        coordinator.controlTextDidEndEditing(.init(name: NSControl.textDidEndEditingNotification, object: field))
        #expect(committed == [0])
        #expect(field.number == 0)
    }
}

import ProjectKit
import Testing

struct NumericAdjustmentTests {
    @Test(arguments: [(100.0, 100.0, 0), (100.0, 99.99, 0), (44.046, 44.0, 1), (0.0, 0.04, 1)])
    func returningToTheDisplayedStartChoosesNoValue(start: Double, end: Double, precision: Int) {
        #expect(NumericAdjustment.valueToCommit(end, startingAt: start, fractionDigits: precision) == nil)
    }

    @Test func comingBackToAPlaceholderChoosesItAndNeverLeavingItChoosesNothing() {
        #expect(NumericAdjustment.valueToCommit(100, startingAt: 100, leftPlaceholder: true) == 100)
        #expect(NumericAdjustment.valueToCommit(100, startingAt: 100, leftPlaceholder: false) == nil)
        #expect(NumericAdjustment.valueToCommit(.nan, startingAt: 100, leftPlaceholder: true) == nil)
    }

    @Test func aChangedGestureChoosesItsFinalValue() throws {
        #expect(NumericAdjustment.valueToCommit(137.6, startingAt: 100) == 138)
        let value = try #require(NumericAdjustment.valueToCommit(45.14, startingAt: 44.046, fractionDigits: 1))
        #expect(abs(value - 45.1) < 0.000_001)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func invalidValuesCannotBecomeACommit(value: Double) {
        #expect(NumericAdjustment.valueToCommit(value, startingAt: 0) == nil)
        #expect(NumericAdjustment.valueToCommit(0, startingAt: value) == nil)
    }
}

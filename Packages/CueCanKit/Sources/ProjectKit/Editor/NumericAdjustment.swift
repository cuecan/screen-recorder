import Foundation

/// Finishes a numeric gesture at its displayed precision. Ending where it started cancels the audition.
///
/// A mixed field has no value of its own, so its thumb or scrub starts at a placeholder. Letting go
/// without moving chooses nothing and the values stay mixed. Moving away and coming back to the
/// placeholder chooses it: the control shows that number at release, and it's the only way to drag
/// several clips to it.
public enum NumericAdjustment {
    /// - Parameter leftPlaceholder: The start was only a placeholder and the gesture moved off it.
    public static func valueToCommit(_ value: Double, startingAt start: Double, fractionDigits: Int = 0,
                                     leftPlaceholder: Bool = false) -> Double? {
        let quantum = pow(10, -Double(fractionDigits))
        guard value.isFinite, start.isFinite, quantum.isFinite, quantum > 0 else { return nil }
        let ending = (value / quantum).rounded() * quantum
        let beginning = (start / quantum).rounded() * quantum
        guard ending.isFinite, beginning.isFinite, ending != beginning || leftPlaceholder else { return nil }
        return ending
    }
}

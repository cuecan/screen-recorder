import Foundation

/// The level meter's colour: green, then amber, then red near 0 dBFS (docs/ui.md, board 1).
public enum LevelZone: Sendable, Equatable {
    case normal, hot, clipping

    /// Amber from −12 dBFS, red from −3. Starting values, to judge by eye.
    public static let hotFrom: Float = -12
    public static let clippingFrom: Float = -3

    public init(peakDecibels: Float) {
        if peakDecibels >= Self.clippingFrom {
            self = .clipping
        } else if peakDecibels >= Self.hotFrom {
            self = .hot
        } else {
            self = .normal
        }
    }
}

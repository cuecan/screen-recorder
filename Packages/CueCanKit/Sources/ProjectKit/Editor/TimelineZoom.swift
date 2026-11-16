import Foundation

/// Timeline zoom in points per second, shared by the slider, shortcuts and fit command.
public enum TimelineZoom {
    public static let range: ClosedRange<Double> = (1.0 / 64)...512
    /// The slider uses powers of two, so it offers useful precision from a long take down to a frame.
    public static var exponentRange: ClosedRange<Double> { log2(range.lowerBound)...log2(range.upperBound) }
    /// Empty space before and after the edit, including the trailing scroll margin.
    public static let horizontalPadding = TimelineLane.leading * 2 + 40

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// Fits the entire edit without creating a horizontal scroller from its own trailing margin.
    public static func fitted(duration: TimeInterval, viewport: Double) -> Double {
        guard duration.isFinite, duration > 0, viewport.isFinite else { return range.lowerBound }
        return clamped((viewport - horizontalPadding) / duration)
    }
}

import CoreGraphics

/// A confirmed placement, including a useful fallback when the exact requested size was refused.
public enum WindowSnapResult: Equatable, Sendable {
    case filled
    case placed(fit: WindowFit, frame: CGRect, placement: WindowFallbackPlacement.Kind)
}

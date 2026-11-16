import CoreGraphics
import Foundation

/// Whether a window could be made to fill the capture area (docs/ui.md, R4).
public enum WindowFit: Sendable, Equatable {
    /// It took the area's size.
    case fits
    /// Its observed width stayed larger than the requested area's width after retries.
    case tooNarrow(minimumWidth: Int)
    /// Its observed height stayed larger than the requested area's height after retries.
    case tooShort(minimumHeight: Int)
    /// Its observed width stayed smaller than the requested area's width after retries.
    case tooSlim(maximumWidth: Int)
    /// Its observed height stayed smaller than the requested area's height after retries.
    case tooLow(maximumHeight: Int)

    /// Edges within this many points count as filling the area.
    public static let tolerance = 1.0

    /// The fit of a window that was asked to take the area's size and ended up at `result`.
    public static func fit(result: CGSize, area: CGSize) -> WindowFit {
        if result.width > area.width + tolerance { return .tooNarrow(minimumWidth: Int(result.width.rounded())) }
        if result.height > area.height + tolerance { return .tooShort(minimumHeight: Int(result.height.rounded())) }
        if result.width < area.width - tolerance { return .tooSlim(maximumWidth: Int(result.width.rounded())) }
        if result.height < area.height - tolerance { return .tooLow(maximumHeight: Int(result.height.rounded())) }
        return .fits
    }

    /// Checks a completed snap in global coordinates. Nil means the size fits but the window did not
    /// reach the requested position; a size constraint still returns its more specific explanation.
    public static func fit(result: CGRect, area: CGRect) -> WindowFit? {
        let fit = fit(result: result.size, area: area.size)
        if fit == .fits, !fills(result, area: area) { return nil }
        return fit
    }

    /// Whether a window's frame already fills the area.
    public static func fills(_ window: CGRect, area: CGRect) -> Bool {
        abs(window.minX - area.minX) <= tolerance && abs(window.minY - area.minY) <= tolerance
            && abs(window.width - area.width) <= tolerance && abs(window.height - area.height) <= tolerance
    }

    /// What to say when the window didn't take the area's size: one short line, with no measurements.
    /// It says what happened, not what the app can do: an app that can grow sometimes
    /// doesn't. Nil when it fits.
    public func notice(appName: String) -> String? {
        switch self {
        case .fits: nil
        case .tooNarrow, .tooShort: "\(appName) was unable to shrink to fit, so part of it is outside the recording."
        case .tooSlim, .tooLow: "\(appName) was unable to grow to fill this area."
        }
    }

    /// Whether most of a window is still inside the area. A window the creator has dragged out of it, or
    /// onto another display, isn't, and is theirs to place.
    public static func isMostlyInside(_ window: CGRect, area: CGRect) -> Bool {
        let shared = window.intersection(area)
        guard !shared.isNull, window.width > 0, window.height > 0 else { return false }
        return shared.width * shared.height >= window.width * window.height / 2
    }

    /// Whether the window ended up smaller than the area in either direction.
    public static func isSmaller(_ result: CGSize, than area: CGSize) -> Bool {
        result.width < area.width - tolerance || result.height < area.height - tolerance
    }
}

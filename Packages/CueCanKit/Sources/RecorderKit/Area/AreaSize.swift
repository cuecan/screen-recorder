import Foundation
import ProjectKit

/// A size for the capture area: the largest a display fits, and the preset heights corners stick at.
public struct AreaSize: Sendable, Equatable, Identifiable {
    public var area: CaptureArea
    /// Whether it fits the display. Sizes that don't are greyed out.
    public var fits: Bool

    public var id: Int { area.heightPoints }

    /// The label above the area's frame (docs/ui.md, R2; docs/decisions.md, 78): how big text will look,
    /// against the largest area of this shape the display fits, where every setup starts. "Text 1.7×",
    /// or "Text 2×" when whole. Nil at the largest size, or anything bigger, since there's nothing to
    /// compare with.
    ///
    /// The screen fills the same slot in the video at any size, so text scales as the largest height over
    /// this one.
    public static func frameLabel(for area: CaptureArea, largest: CaptureArea?) -> String? {
        guard let largest, area.heightPoints > 0 else { return nil }
        let scale = (Double(largest.heightPoints) / Double(area.heightPoints) * 10).rounded() / 10
        guard scale > 1 else { return nil }
        return "Text \(scale.formatted(.number.precision(.fractionLength(0...1))))×"
    }

    /// The largest area that fits, followed by the preset heights. Every format can use the full
    /// available height (or width, when that is the limiting edge).
    public static func options(for ratio: CaptureArea.Ratio, displayWidth: Double, displayHeight: Double) -> [AreaSize] {
        var sizes = CaptureArea.presetHeights.map { height in
            let area = CaptureArea(ratio: ratio, heightPoints: height)
            return AreaSize(area: area, fits: area.fits(width: displayWidth, height: displayHeight))
        }
        if let largest = CaptureArea.largest(ratio, fittingWidth: displayWidth, height: displayHeight),
            !sizes.contains(where: { $0.area == largest })
        {
            sizes.insert(AreaSize(area: largest, fits: true), at: 0)
        }
        return sizes.sorted { lhs, rhs in
            if lhs.fits != rhs.fits { return lhs.fits }
            return lhs.area.heightPoints > rhs.area.heightPoints
        }
    }

    /// The size to start with: the largest that fits.
    public static func defaultOption(for ratio: CaptureArea.Ratio, displayWidth: Double, displayHeight: Double) -> AreaSize? {
        options(for: ratio, displayWidth: displayWidth, displayHeight: displayHeight).first(where: \.fits)
    }
}

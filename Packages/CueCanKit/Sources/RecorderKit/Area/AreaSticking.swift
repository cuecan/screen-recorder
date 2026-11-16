import CoreGraphics
import Foundation
import ProjectKit

/// How the capture area sticks while it's dragged (docs/decisions.md, 19).
///
/// A corner sticks briefly at each preset height (1080, 810 and 540 pt) and at the largest size the
/// display fits, so the sizes that make text sharp are easy to land on. A moved area's edges stick to the
/// display's sides, so it's easy to push it all the way to one side.
public enum AreaSticking {
    /// How far, in points, the pointer has to travel past a sticking point before the area moves on.
    public static let distance: Double = 10

    /// The heights a corner sticks at: the presets that fit, and the largest area that fits the display.
    public static func heights(for ratio: CaptureArea.Ratio, display: CGRect) -> [Int] {
        var heights = CaptureArea.presetHeights.filter {
            CaptureArea(ratio: ratio, heightPoints: $0).fits(width: display.width, height: display.height)
        }
        if let largest = CaptureArea.largest(ratio, fittingWidth: display.width, height: display.height),
            !heights.contains(largest.heightPoints)
        {
            heights.append(largest.heightPoints)
        }
        return heights.sorted(by: >)
    }

    /// A height pulled to the nearest sticking height when it's within ``distance`` of one.
    public static func stuck(height: Double, to heights: [Int], distance: Double = Self.distance) -> Double {
        guard let nearest = heights.min(by: { abs(Double($0) - height) < abs(Double($1) - height) }),
            abs(Double(nearest) - height) <= distance
        else { return height }
        return Double(nearest)
    }

    /// A corner dragged to resize the area, with its shape locked, its opposite corner fixed, and the
    /// height sticking at the presets and at the largest size.
    ///
    /// - Parameter display: The display's available desktop, which the area stays inside.
    public static func resized(
        _ original: CGRect, corner: AreaGeometry.Corner, translation: CGSize,
        ratio: CaptureArea.Ratio, within display: CGRect
    ) -> CGRect {
        let anchor = CGPoint(x: corner.isLeft ? original.maxX : original.minX,
                             y: corner.isBottom ? original.maxY : original.minY)
        let availableWidth = corner.isLeft ? anchor.x - display.minX : display.maxX - anchor.x
        let availableHeight = corner.isBottom ? anchor.y - display.minY : display.maxY - anchor.y
        guard let maximum = CaptureArea.largest(ratio, fittingWidth: availableWidth, height: availableHeight) else { return original }
        let dx = translation.width * (corner.isLeft ? -1 : 1)
        let dy = translation.height * (corner.isBottom ? -1 : 1)
        // The pointer projected onto the shape's diagonal, so either axis feels natural.
        let change = (dx * ratio.aspect + dy) / (ratio.aspect * ratio.aspect + 1)
        let sticking = heights(for: ratio, display: display) + [maximum.heightPoints]
        let wanted = stuck(height: original.height + change, to: sticking)
        let smallest = min(AreaGeometry.smallestHeight, maximum.heightPoints)
        let height = min(maximum.heightPoints, max(smallest, Int((wanted / 2).rounded()) * 2))
        let area = CaptureArea(ratio: ratio, heightPoints: height)
        return CGRect(x: corner.isLeft ? anchor.x - Double(area.widthPoints) : anchor.x,
                      y: corner.isBottom ? anchor.y - Double(height) : anchor.y,
                      width: Double(area.widthPoints), height: Double(height))
    }

    /// The area moved by a drag, kept on the display, with each edge pulled to the display's side when it
    /// comes within ``distance`` of it.
    public static func moved(_ original: CGRect, by translation: CGSize, within display: CGRect) -> CGRect {
        var frame = AreaGeometry.clamped(original.offsetBy(dx: translation.width, dy: translation.height), to: display)
        if abs(frame.minX - display.minX) <= distance { frame.origin.x = display.minX }
        else if abs(frame.maxX - display.maxX) <= distance { frame.origin.x = display.maxX - frame.width }
        if abs(frame.minY - display.minY) <= distance { frame.origin.y = display.minY }
        else if abs(frame.maxY - display.maxY) <= distance { frame.origin.y = display.maxY - frame.height }
        return frame
    }

    /// The smallest area of a shape that holds a window of at least this size, for "Use a bigger area".
    ///
    /// - Returns: Nil when even the largest area the display fits is too small for the window.
    public static func smallestArea(_ ratio: CaptureArea.Ratio, holding minimum: CGSize, display: CGRect) -> CaptureArea? {
        guard let largest = CaptureArea.largest(ratio, fittingWidth: display.width, height: display.height) else { return nil }
        var height = max(AreaGeometry.smallestHeight, Int(minimum.height.rounded(.up)))
        height += height % 2
        while height <= largest.heightPoints {
            let area = CaptureArea(ratio: ratio, heightPoints: height)
            if Double(area.widthPoints) >= minimum.width.rounded(.up) { return area }
            height += 2
        }
        return nil
    }
}

extension AreaGeometry {
    /// The smallest height a dragged corner can make the area.
    public static let smallestHeight = 180
}

import CoreGraphics
import Foundation
import ProjectKit

/// Where the capture area sits, in the two coordinate systems that meet here.
///
/// AppKit places windows in global coordinates from the bottom left of the main display, with y up.
/// ScreenCaptureKit crops a display capture with `sourceRect` in that display's own points, from its top
/// left, with y down.
public enum AreaGeometry {
    /// The area as `sourceRect` for a display capture, from a frame in AppKit's global coordinates.
    public static func sourceRect(for area: CGRect, onDisplay display: CGRect) -> CGRect {
        CGRect(x: area.minX - display.minX, y: display.maxY - area.maxY, width: area.width, height: area.height)
    }

    /// The area moved as little as possible to lie inside the display, with whole-point edges.
    public static func clamped(_ area: CGRect, to display: CGRect) -> CGRect {
        let width = min(area.width, display.width)
        let height = min(area.height, display.height)
        let x = min(max(area.minX, display.minX), display.maxX - width).rounded()
        let y = min(max(area.minY, display.minY), display.maxY - height).rounded()
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// An area of a size centered on a display.
    public static func centered(width: Double, height: Double, on display: CGRect) -> CGRect {
        clamped(CGRect(x: display.midX - width / 2, y: display.midY - height / 2, width: width, height: height), to: display)
    }

    /// The four strips of a display outside the area, for the dimming that sits outside it.
    public static func dimming(around area: CGRect, on display: CGRect) -> [CGRect] {
        let inside = area.intersection(display)
        guard !inside.isNull else { return [display] }
        return [
            CGRect(x: display.minX, y: inside.maxY, width: display.width, height: display.maxY - inside.maxY),
            CGRect(x: display.minX, y: display.minY, width: display.width, height: inside.minY - display.minY),
            CGRect(x: display.minX, y: inside.minY, width: inside.minX - display.minX, height: inside.height),
            CGRect(x: inside.maxX, y: inside.minY, width: display.maxX - inside.maxX, height: inside.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    /// Keeps an existing selection valid after the display changes size or position. The aspect ratio
    /// is preserved even when the old selection is larger than the newly available space.
    public static func refitted(_ frame: CGRect, ratio: CaptureArea.Ratio, to display: CGRect) -> CGRect? {
        guard let maximum = CaptureArea.largest(ratio, fittingWidth: display.width, height: display.height) else { return nil }
        let height = min(maximum.heightPoints, max(2, Int(frame.height)))
        let area = CaptureArea(ratio: ratio, heightPoints: height)
        let centered = CGRect(x: frame.midX - Double(area.widthPoints) / 2, y: frame.midY - Double(height) / 2,
                              width: Double(area.widthPoints), height: Double(height))
        return clamped(centered, to: display)
    }

    /// A corner dragged to resize an area while keeping its opposite corner fixed.
    public enum Corner: CaseIterable, Sendable {
        case bottomLeft, bottomRight, topLeft, topRight

        public var isLeft: Bool { self == .bottomLeft || self == .topLeft }
        public var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
    }

}

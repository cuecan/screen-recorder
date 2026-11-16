import CoreGraphics
import Foundation

/// Where the setup bar and the Recording Panel first appear (docs/ui.md, R2; docs/decisions.md, 20 and 49).
/// After that the creator owns their positions: neither moves when the format or the size changes.
public enum ControlPlacement {
    /// The gap between a control and the display's edge, or the area's frame.
    public static let margin: CGFloat = 16

    /// The setup bar: at the bottom centre of the display's available desktop, outside the area when
    /// there's room below or above it, and over the area otherwise, since it hides on Record.
    ///
    /// - Parameters:
    ///   - area: The capture area, when a format is already chosen.
    ///   - display: The display's available desktop, in AppKit's global coordinates.
    public static func setupBar(size: CGSize, area: CGRect?, display: CGRect) -> CGRect {
        let x = (display.midX - size.width / 2).rounded()
        let bottom = CGRect(x: x, y: display.minY + margin, width: size.width, height: size.height)
        guard let area, bottom.intersects(area.insetBy(dx: -AreaGeometry.outlineWidth, dy: -AreaGeometry.outlineWidth)) else {
            return bottom
        }
        let below = CGRect(x: x, y: area.minY - margin - size.height, width: size.width, height: size.height)
        if below.minY >= display.minY { return below }
        let above = CGRect(x: x, y: area.maxY + margin, width: size.width, height: size.height)
        if above.maxY <= display.maxY { return above }
        return bottom
    }

    /// The Recording Panel: beside the area, on its right and then its left, lined up with its top, when
    /// there's room; otherwise in the display's top right corner.
    public static func panel(size: CGSize, area: CGRect?, display: CGRect) -> CGRect {
        let corner = CGRect(x: display.maxX - margin - size.width, y: display.maxY - margin - size.height,
                            width: size.width, height: size.height)
        guard let area else { return corner }
        let top = min(area.maxY, display.maxY - margin) - size.height
        let y = max(display.minY + margin, top)
        let right = CGRect(x: area.maxX + margin, y: y, width: size.width, height: size.height)
        if right.maxX <= display.maxX - margin { return right }
        let left = CGRect(x: area.minX - margin - size.width, y: y, width: size.width, height: size.height)
        if left.minX >= display.minX + margin { return left }
        return corner
    }
}

extension AreaGeometry {
    /// The width of the area's outline while setting up, drawn outside the area.
    public static let outlineWidth: CGFloat = 2
}

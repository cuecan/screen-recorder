import CoreGraphics
import Foundation
import SwiftUI

/// The outline of a tile, as macOS 26 and 27 draw their windows and controls: corners with continuous
/// curvature, Apple's `.continuous` corner style, rather than a quarter circle.
///
/// A plain corner radius joins a straight edge to a circular arc, so the curvature jumps from none to full
/// at one point, which reads as a slight kink. A continuous corner eases the curve in over a longer stretch of
/// each edge, like a squircle, so the same radius looks softer and larger. The shape is SwiftUI's own
/// `RoundedRectangle(style: .continuous)`, the one the system uses, so tiles match the windows in them.
/// Apple doesn't publish the curve's formula.
public enum TileShape {
    /// The outline of a placement in its frame, from the frame's top left, y going down.
    public static func path(for placement: Placement, in rect: CGRect) -> CGPath {
        path(corners: placement.corners, in: rect)
    }

    /// An outline with these corners, each kept to half the shorter side, from the top left, y going down.
    public static func path(corners: Corners, in rect: CGRect) -> CGPath {
        let corners = corners.limited(to: rect.size)
        guard !corners.isSquare else { return CGPath(rect: rect, transform: nil) }
        let radii = RectangleCornerRadii(topLeading: corners.topLeft, bottomLeading: corners.bottomLeft,
                                         bottomTrailing: corners.bottomRight, topTrailing: corners.topRight)
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect).cgPath
    }

    /// The outline for drawing into a Core Graphics bitmap, whose y goes up: the corners mirrored top to
    /// bottom, so the image comes out the right way up.
    static func bitmapPath(for placement: Placement, in rect: CGRect) -> CGPath {
        path(corners: placement.corners.mirroredDown, in: rect)
    }

    /// The placement's edge: a band `width` wide just inside its outline, white on clear, `size` big. It's
    /// the outline stroked twice as wide and clipped to the outline, so it's exactly even all the way round,
    /// corners included. (A smaller copy of a continuous corner isn't parallel to it, so cutting one out of
    /// the other made the band thicker at the corners.)
    static func borderMask(for placement: Placement, size: CGSize, width: Double) -> CGImage? {
        let pixelWidth = max(1, Int(size.width.rounded())), pixelHeight = max(1, Int(size.height.rounded()))
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        let outline = bitmapPath(for: placement, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setShouldAntialias(true)
        context.addPath(outline)
        context.clip()
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineWidth(width * 2)
        context.addPath(outline)
        context.strokePath()
        return context.makeImage()
    }

    /// The hairline's colour on a background: dark and faint on a light one, light and faint on a dark one,
    /// so the edge reads on any background without looking drawn on. As grey and opacity.
    /// The values are starting points, to judge by eye.
    public static func hairline(on background: (red: Double, green: Double, blue: Double)) -> (gray: Double, alpha: Double) {
        // Relative luminance, Rec. 709 weights on the sRGB values: close enough to pick a side.
        let luminance = 0.2126 * background.red + 0.7152 * background.green + 0.0722 * background.blue
        return luminance > 0.5 ? (0, 0.14) : (1, 0.18)
    }

    /// A white mask of a placement's outline, `size` big, on clear, for Core Image. Antialiased.
    static func mask(for placement: Placement, size: CGSize) -> CGImage? {
        let width = max(1, Int(size.width.rounded())), height = max(1, Int(size.height.rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setShouldAntialias(true)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(bitmapPath(for: placement, in: CGRect(x: 0, y: 0, width: width, height: height)))
        context.fillPath()
        return context.makeImage()
    }
}

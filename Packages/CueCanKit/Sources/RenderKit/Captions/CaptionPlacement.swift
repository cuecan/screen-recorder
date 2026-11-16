import CoreGraphics
import Foundation
import ProjectKit

/// Where captions sit in one clip's frame, from the pictures ``LayoutGeometry`` placed: pure maths on
/// rectangles, so it's tested without drawing (docs/decisions.md, 80).
public enum CaptionPlacement {
    /// How a block of lines sits against its area's anchor line.
    public enum Alignment: Hashable, Sendable {
        /// The block's top is at the anchor.
        case top
        /// The block's middle is at the anchor.
        case centre
        /// The block's bottom is at the anchor.
        case bottom
    }

    /// Where a style's text goes in a frame.
    public struct Area: Hashable, Sendable {
        /// The horizontal stretch the lines are centred in and may not be wider than, in pixels from the left.
        public var left: Double
        public var right: Double
        /// The line the block is aligned to, in pixels from the top.
        public var anchor: Double
        public var alignment: Alignment
        /// What decided it, for preview_frames and the tests.
        public var reason: Reason

        public var width: Double { right - left }
        public var midX: Double { (left + right) / 2 }

        /// The top of a block `height` tall.
        public func top(of height: Double) -> Double {
            switch alignment {
            case .top: anchor
            case .centre: anchor - height / 2
            case .bottom: anchor - height
            }
        }
    }

    public enum Reason: String, Hashable, Sendable {
        /// A band no picture covers, tall enough for the text.
        case freeBand
        /// Where a screen and a camera stacked one above the other meet.
        case seam
        /// Low over the pictures, clear of the camera.
        case low
        /// The style asked for the bottom, the middle or the top.
        case asked
    }

    /// How much of the frame's height is kept clear at the top and bottom edge. A starting value: where each
    /// platform's own buttons and captions cover a Short is VERIFY, so no platform's numbers are used.
    public static let edgeMargin = 0.08
    /// How much room a free band needs beyond one line, as a multiple of the line's height.
    public static let bandRoom = 1.3
    /// The gap kept between the text and a picture it sits beside, as a multiple of the line's height.
    public static let clearance = 0.25

    /// Where a style's text goes in a frame of `size` showing `pictures`, the camera's among them.
    ///
    /// - Parameter lineHeight: One line of the style at this frame's size, in pixels.
    public static func area(style: CaptionStyle, size: CGSize, screen: CGRect?, camera: CGRect?, lineHeight: Double) -> Area {
        let width = Double(size.width), height = Double(size.height)
        let margin = edgeMargin * height
        let shift = style.offset * height
        let pictures = [screen, camera].compactMap { $0 }.filter { $0.width > 0 && $0.height > 0 }

        func clear(_ area: Area, strip: ClosedRange<Double>) -> Area {
            var area = area
            let span = widestClearSpan(of: 0...width, avoiding: camera, over: strip)
            area.left = span.lowerBound
            area.right = span.upperBound
            area.anchor += shift
            return area
        }
        func low() -> Area {
            let bottom = height - margin
            return clear(Area(left: 0, right: width, anchor: bottom, alignment: .bottom, reason: style.position == .free ? .low : .asked),
                         strip: (bottom - lineHeight * 2)...bottom)
        }

        switch style.position {
        case .bottom: return low()
        case .top:
            return clear(Area(left: 0, right: width, anchor: margin, alignment: .top, reason: .asked), strip: margin...(margin + lineHeight * 2))
        case .middle:
            return clear(Area(left: 0, right: width, anchor: height / 2, alignment: .centre, reason: .asked),
                         strip: (height / 2 - lineHeight)...(height / 2 + lineHeight))
        case .free:
            break
        }

        // A free band: the tallest stretch of the height no picture touches, inside the edge margins.
        let bands = freeBands(height: height, pictures: pictures)
            .map { (low: max($0.lowerBound, margin), high: min($0.upperBound, height - margin)) }
            .filter { $0.high - $0.low >= lineHeight * bandRoom }
            .map { $0.low...$0.high }
        if let band = bands.max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }) {
            var area = Area(left: 0, right: width, anchor: (band.lowerBound + band.upperBound) / 2, alignment: .centre, reason: .freeBand)
            area.anchor += shift
            return area
        }

        // A seam: the screen and the camera one above the other, as a Short's Split or Card stacks them.
        if let screen, let camera, stacked(screen, camera) {
            let (upper, lower) = screen.midY < camera.midY ? (screen, camera) : (camera, screen)
            let pad = lineHeight * clearance
            var area: Area
            if lower.minY >= upper.maxY {
                // A gap between them, too short for the text: straddle it.
                area = Area(left: 0, right: width, anchor: (upper.maxY + lower.minY) / 2, alignment: .centre, reason: .seam)
            } else if lower == camera {
                // A card over the screen's lower edge: just above the card, over the screen.
                area = Area(left: 0, right: width, anchor: lower.minY - pad, alignment: .bottom, reason: .seam)
            } else {
                // A card over the screen's upper edge: just below it, over the screen.
                area = Area(left: 0, right: width, anchor: upper.maxY + pad, alignment: .top, reason: .seam)
            }
            area.anchor += shift
            return area
        }
        return low()
    }

    /// The stretches of a frame's height that no picture covers, top to bottom.
    public static func freeBands(height: Double, pictures: [CGRect]) -> [ClosedRange<Double>] {
        let covered = pictures.map { Double($0.minY)...Double($0.maxY) }.sorted { $0.lowerBound < $1.lowerBound }
        var bands: [ClosedRange<Double>] = []
        var cursor = 0.0
        for range in covered {
            if range.lowerBound > cursor { bands.append(cursor...range.lowerBound) }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < height { bands.append(cursor...height) }
        return bands
    }

    /// Whether two pictures sit one above the other: they share most of their width, and one's middle is
    /// above the other's top.
    static func stacked(_ a: CGRect, _ b: CGRect) -> Bool {
        let shared = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let (upper, lower) = a.midY < b.midY ? (a, b) : (b, a)
        return shared >= 0.5 * min(a.width, b.width) && upper.midY < lower.minY && lower.midY > upper.maxY
    }

    /// The widest part of `span` that `camera` doesn't cover where it overlaps the vertical `strip`.
    static func widestClearSpan(of span: ClosedRange<Double>, avoiding camera: CGRect?, over strip: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let camera, Double(camera.maxY) > strip.lowerBound, Double(camera.minY) < strip.upperBound,
              Double(camera.maxX) > span.lowerBound, Double(camera.minX) < span.upperBound
        else { return span }
        var parts: [ClosedRange<Double>] = []
        if Double(camera.minX) > span.lowerBound { parts.append(span.lowerBound...Double(camera.minX)) }
        if Double(camera.maxX) < span.upperBound { parts.append(Double(camera.maxX)...span.upperBound) }
        return parts.max { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound } ?? span
    }
}

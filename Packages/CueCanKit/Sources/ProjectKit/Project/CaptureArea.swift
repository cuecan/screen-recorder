import Foundation

/// The area of the display that a screen recording captured (docs/design.md, "Capture areas").
///
/// Its shape comes from the layout chosen in the setup's Layout choices (docs/decisions.md, 89). The shape is what lets each output be laid out without squashing or cropping
/// the screen.
public struct CaptureArea: Codable, Equatable, Sendable {
    /// The shapes a layout can record (docs/decisions.md, 89). The setup shows them as "Screen 4:3".
    public enum Ratio: String, Codable, Sendable, CaseIterable {
        /// The whole frame of a 16:9 video: Card.
        case sixteenByNine = "16:9"
        /// Side by side in the video, the camera a quarter of the width.
        case fourByThree = "4:3"
        /// Side by side in the video, the camera a third.
        case thirtyTwoByTwentySeven = "32:27"
        /// Side by side in the video, the camera half.
        case eightByNine = "8:9"
        /// The whole frame of a 9:16 Short: Card.
        case nineBySixteen = "9:16"
        /// Side by side in the Short, the camera a quarter of the height.
        case threeByFour = "3:4"
        /// Side by side in the Short, the camera a third.
        case twentySevenByThirtyTwo = "27:32"
        /// Side by side in the Short, the camera half; and Wide for Both: the video's height and the Short's
        /// width.
        case nineByEight = "9:8"
        /// Square for Both: nearly even in each output.
        case square = "1:1"

        /// Width over height.
        public var aspect: Double {
            let parts = rawValue.split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 ? parts[0] / parts[1] : 1
        }

        /// The area's width in points for a height, rounded to the nearest even number.
        public func width(forHeight height: Int) -> Int {
            let exact = Double(height) * aspect
            return Int((exact / 2).rounded()) * 2
        }
    }

    /// The preset heights in points. A smaller area means bigger text once it's scaled to the video.
    public static let presetHeights = [1080, 810, 540]

    public var ratio: Ratio
    /// The area's size in points. Retina displays capture twice as many pixels.
    public var widthPoints: Int
    public var heightPoints: Int

    /// An area of a preset height. The width follows from the ratio.
    public init(ratio: Ratio, heightPoints: Int) {
        self.ratio = ratio
        self.heightPoints = heightPoints
        self.widthPoints = ratio.width(forHeight: heightPoints)
    }

    /// The largest area of a ratio that fits a display, with an even height. This is the default for
    /// every shape, which for 16:9 on a 16:9 or 16:10 display is the display's full width.
    ///
    /// - Returns: Nil if no area of at least 2 points fits.
    public static func largest(_ ratio: Ratio, fittingWidth width: Double, height: Double) -> CaptureArea? {
        var candidate = Int(min(height, width / ratio.aspect) / 2) * 2
        while candidate > 0, Double(ratio.width(forHeight: candidate)) > width {
            candidate -= 2
        }
        return candidate > 0 ? CaptureArea(ratio: ratio, heightPoints: candidate) : nil
    }

    /// Whether the area fits a display of this size in points. Sizes that don't are greyed out.
    public func fits(width: Double, height: Double) -> Bool {
        Double(widthPoints) <= width && Double(heightPoints) <= height
    }
}

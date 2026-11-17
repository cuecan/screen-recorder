import CoreGraphics
import Foundation
import ProjectKit

/// A size picked from the capture area's menu: the largest the display fits, with or without its menu bar,
/// or a part of that.
///
/// The parts are fractions of the largest area on the desktop, so they mean the same on every display and
/// in every shape.
public enum AreaChoice: CaseIterable, Sendable {
    /// The largest area the whole display fits, at its top, over the menu bar.
    case largestWithMenuBar
    /// The largest area the desktop fits, under the menu bar. Every setup starts here.
    case largest
    case twoThirds
    case half
    case third

    public var title: String {
        switch self {
        case .largestWithMenuBar: "Largest with menu bar"
        case .largest: "Largest"
        // How much bigger the text comes out than at the largest size, as the label over the area says it.
        case .twoThirds: "Text 1.5×"
        case .half: "Text 2×"
        case .third: "Text 3×"
        }
    }

    /// The share of the largest area's height. Nil for the two that are the largest itself.
    private var share: Double? {
        switch self {
        case .largestWithMenuBar, .largest: nil
        case .twoThirds: 2.0 / 3
        case .half: 1.0 / 2
        case .third: 1.0 / 3
        }
    }

    /// The choices a display offers, largest first.
    ///
    /// The menu bar's row is left out when the desktop already reaches the top of the display, as it does
    /// with the menu bar hidden. A part too small to drag to isn't offered either.
    ///
    /// - Parameters:
    ///   - desktop: The display's available desktop, in AppKit's coordinates.
    ///   - display: The whole display.
    public static func offered(for ratio: CaptureArea.Ratio, desktop: CGRect, display: CGRect) -> [AreaChoice] {
        allCases.filter { choice in
            if choice == .largestWithMenuBar, display.maxY <= desktop.maxY { return false }
            guard let area = choice.area(for: ratio, desktop: desktop, display: display) else { return false }
            return choice.share == nil || area.heightPoints >= AreaGeometry.smallestHeight
        }
    }

    /// The size this choice gives on a display. Nil when no area of the shape fits.
    public func area(for ratio: CaptureArea.Ratio, desktop: CGRect, display: CGRect) -> CaptureArea? {
        let bounds = self == .largestWithMenuBar ? display : desktop
        guard let largest = CaptureArea.largest(ratio, fittingWidth: bounds.width, height: bounds.height) else { return nil }
        guard let share else { return largest }
        // An even height, like every area's.
        let height = Int((Double(largest.heightPoints) * share / 2).rounded()) * 2
        return height >= 2 ? CaptureArea(ratio: ratio, heightPoints: height) : nil
    }

    /// Where the area goes when this is picked: around the middle of where it was, kept on the desktop.
    /// With the menu bar, it goes to the top of the display.
    public func frame(for ratio: CaptureArea.Ratio, from current: CGRect, desktop: CGRect, display: CGRect) -> CGRect? {
        guard let area = area(for: ratio, desktop: desktop, display: display) else { return nil }
        let size = CGSize(width: Double(area.widthPoints), height: Double(area.heightPoints))
        let centred = CGRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2, width: size.width, height: size.height)
        guard self == .largestWithMenuBar else { return AreaGeometry.clamped(centred, to: desktop) }
        var frame = AreaGeometry.clamped(centred, to: display)
        frame.origin.y = display.maxY - frame.height
        return frame
    }

    /// The choice an area matches, for the menu's tick. Nil for a size dragged to in between.
    public static func matching(_ frame: CGRect, ratio: CaptureArea.Ratio, desktop: CGRect, display: CGRect) -> AreaChoice? {
        let overMenuBar = frame.maxY > desktop.maxY
        return offered(for: ratio, desktop: desktop, display: display).first { choice in
            guard let area = choice.area(for: ratio, desktop: desktop, display: display),
                  Int(frame.height) == area.heightPoints else { return false }
            return (choice == .largestWithMenuBar) == overMenuBar
        }
    }
}

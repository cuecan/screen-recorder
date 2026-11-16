import CoreGraphics
import Foundation
import ProjectKit

/// The setup element's sizes (docs/ui.md, R10; docs/decisions.md, 79): one window while setting up, the
/// live preview of the export in a dark well above the two-row strip, under a 30 pt title bar.
public enum SetupElementLayout {
    /// The strip's width plus an 8 pt margin each side.
    public static let width: Double = 656
    /// The title bar, edge to edge.
    public static let headerHeight: Double = 30
    /// The space above and below the preview in its well.
    public static let wellPadding: Double = 12
    /// Everything but the preview: the title bar, the well's padding, the strip's two rows and the margin
    /// under them, as measured on the board (365 pt for a 200 pt preview).
    public static let chromeHeight: Double = 165
    /// The smallest preview a short display gets, so the cap never squeezes it to nothing.
    public static let minimumPreviewHeight: Double = 120

    /// The preview's height: the panel's (200 pt, 427 for Vertical's Short), or less on a short display,
    /// the most that keeps the element within half the display's visible height (Claude's proposal,
    /// AUTHOR'S TAKE NEEDED). Only Vertical is ever affected on today's Macs: a 307 pt Short on a display with
    /// 945 pt visible.
    public static func previewHeight(for destination: VideoFormat.Destination?, visibleHeight: Double) -> Double {
        let standard = RecordingPanelLayout.previewHeight(for: destination)
        let room = (visibleHeight / 2 - chromeHeight).rounded(.down)
        return max(minimumPreviewHeight, min(standard, room))
    }

    /// The element's height for a preview, with the Layout menu's height when it's open inside it.
    public static func height(previewHeight: Double, menuHeight: Double = 0) -> Double {
        previewHeight + chromeHeight + menuHeight
    }
}

/// What fills the setup element's well besides the live preview: the Layout choices and framing each take
/// the preview's place, so the element never changes size (docs/ui.md, R10). Sizes follow
/// the board (`RecSetupElement.dc.html`).
public enum SetupWellLayout {
    /// The Layout choices' title row, with the kind and the close button.
    public static let choicesTitleRow: Double = 24
    /// The gap under the title row, and the screen's shape under the picture with its gap.
    static let choicesChrome: Double = 6 + 22
    /// The column of settings beside the picture, and the gap between the two.
    public static let choicesControlsWidth: Double = 268
    public static let choicesGap: Double = 22

    /// The picture's height in the Layout choices (docs/ui/mockups/LayoutsTwoKinds.html, S-A to S-F): as
    /// tall as the well allows under the title row and over the screen's shape, and no wider than the room
    /// beside the settings. 150 pt in Landscape (267 × 150), 143 pt in Both (a video beside its Short), and
    /// the well's height less 52 pt in Vertical.
    ///
    /// - Parameter previewHeight: The preview's height, which the well is sized around.
    public static func choicePictureHeight(previewHeight: Double, destination: VideoFormat.Destination) -> Double {
        let byHeight = previewHeight - choicesTitleRow - choicesChrome
        let room = SetupElementLayout.width - 16 - 24 - choicesControlsWidth - choicesGap - (destination == .both ? 4 : 0)
        return max(1, min(byHeight, room / widthPerHeight(destination)).rounded(.down))
    }

    /// How wide a layout's picture is per point of height: one output, or Both's video beside its Short.
    static func widthPerHeight(_ destination: VideoFormat.Destination) -> Double {
        switch destination {
        case .landscape: 16.0 / 9
        case .vertical: 9.0 / 16
        case .both: 16.0 / 9 + 9.0 / 16
        }
    }

    /// Framing in the well: the whole 16:9 camera frame, and whether the slot tabs, the frame and the zoom
    /// row stack, or the frame sits between a column of tabs on its left and one of zoom, Reset and Done on
    /// its right.
    public struct Framing: Equatable, Sendable {
        public var isStacked: Bool
        /// The camera frame's size, 16:9.
        public var frame: CGSize
    }

    /// The side columns, each 116 pt, and the 12 pt gaps beside the frame.
    public static let framingColumn: Double = 116
    /// The stacked layout's tabs row (only with tabs) and zoom row, and the gaps between them.
    static let framingTabsRow: Double = 30
    static let framingZoomRow: Double = 34

    /// The framing view's layout for a well around a preview of `previewHeight`: stacked where that gives a
    /// bigger frame, as in Vertical (616 × 346 pt), side by side otherwise, as in Landscape and Both (the frame
    /// at the preview's height, 356 × 200 pt).
    public static func framing(previewHeight: Double, hasTabs: Bool) -> Framing {
        let inner = SetupElementLayout.width - 16 - 24
        let stackedHeight = min(inner * 9 / 16, previewHeight - (hasTabs ? framingTabsRow : 0) - framingZoomRow)
        let sideHeight = min(previewHeight, (inner - 2 * (framingColumn + 12)) * 9 / 16)
        let stacked = stackedHeight > sideHeight
        let height = (stacked ? stackedHeight : sideHeight).rounded(.down)
        return Framing(isStacked: stacked, frame: CGSize(width: (height * 16 / 9).rounded(.up), height: height))
    }

    /// Why the framing circle is dimmed, or nil when there's a camera to frame (docs/ui.md, R10).
    public static func framingBlocker(hasFormat: Bool, cameraOn: Bool, cameraHasPicture: Bool) -> String? {
        if !hasFormat { return "Pick where you’ll post it first" }
        if !cameraOn { return "No camera to frame" }
        if !cameraHasPicture { return "Waiting for the camera’s picture" }
        return nil
    }
}

/// Where the setup element goes as its height changes (docs/ui.md, R10): the strip stays put and the well
/// grows upward, so the controls under the pointer don't move when the format changes the preview's height.
/// With no room above, the element moves down instead. The Layout choices and framing never change it.
public enum SetupElementPlacement {
    /// The element at a new height, its bottom edge (the strip) kept where it was, unless that would put its
    /// top off the display; then it moves down just enough. Kept inside the display's available desktop.
    ///
    /// - Parameters:
    ///   - frame: The element's frame now, in AppKit's global coordinates (y up).
    ///   - visible: The display's available desktop.
    public static func resized(_ frame: CGRect, toHeight height: CGFloat, within visible: CGRect) -> CGRect {
        var resized = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        if resized.maxY > visible.maxY { resized.origin.y = visible.maxY - height }
        return AreaGeometry.clamped(resized, to: visible)
    }

    /// Where the element first appears on a display: the bottom centre, outside the area when there's
    /// room, as the setup bar did (``ControlPlacement/setupBar(size:area:display:)``).
    public static func first(size: CGSize, area: CGRect?, display: CGRect) -> CGRect {
        ControlPlacement.setupBar(size: size, area: area, display: display)
    }
}

/// Where the setup element was last put on each display (docs/decisions.md, 79: two places per display,
/// the element's here and the recording panel's in ``RecordingPanelMemory``).
///
/// Kept as the strip's bottom left corner relative to its display, since the strip is what stays put.
public struct SetupElementPlaces: Codable, Equatable, Sendable {
    /// The element's bottom left corner on each display, relative to the display's bottom left, by the
    /// display's persistent id.
    public private(set) var spots: [String: CGPoint]

    public init(spots: [String: CGPoint] = [:]) {
        self.spots = spots
    }

    /// Notes where the element is now.
    ///
    /// - Parameters:
    ///   - frame: The element's frame, in AppKit's global coordinates.
    ///   - displayFrame: The frame of the display it's on.
    public mutating func remember(_ frame: CGRect, on display: String, displayFrame: CGRect) {
        spots[display] = CGPoint(x: frame.minX - displayFrame.minX, y: frame.minY - displayFrame.minY)
    }

    /// Where the element goes on a display it has been on, at its size now, kept inside the display's
    /// available desktop. Nil if it has never been there.
    public func frame(on display: String, size: CGSize, displayFrame: CGRect, visible: CGRect) -> CGRect? {
        guard let spot = spots[display] else { return nil }
        let frame = CGRect(x: displayFrame.minX + spot.x, y: displayFrame.minY + spot.y, width: size.width, height: size.height)
        return SetupElementPlacement.resized(frame, toHeight: size.height, within: visible)
    }
}

import CoreGraphics
import Foundation
import ProjectKit

/// What the Recording Panel shows during a take, switched by the toggle in its header (docs/ui.md, R6;
/// docs/decisions.md, 82).
public enum RecordingPanelShows: String, Codable, Sendable, CaseIterable {
    /// The live preview of the export, its tiles filling the panel's width.
    case preview
    /// The camera alone, in a square as wide as the panel's content, cropped around the main camera slot's
    /// framing.
    case camera
}

/// The Recording Panel's sizes (docs/ui.md, R6; docs/decisions.md, 82): one panel, resizable, whose width
/// sets the picture's size. The header (22 pt), mic row (22 pt) and controls (32 pt) keep their size, with
/// 10 pt padding and 8 pt between, and the height follows the width.
public enum RecordingPanelLayout {
    /// The padding around the panel's content.
    public static let padding: Double = 10
    /// The gap between the panel's rows, and between the preview's tiles.
    public static let spacing: Double = 8
    public static let previewSpacing: Double = spacing
    public static let headerHeight: Double = 22
    public static let micRowHeight: Double = 22
    public static let controlsHeight: Double = 32
    /// Everything but the picture: the padding, the header, the mic row, the controls and the gaps between
    /// them (120 pt).
    public static let chromeHeight: Double = 2 * padding + headerHeight + micRowHeight + controlsHeight + 3 * spacing
    /// The narrowest the header fits at: a dot, "Recording", a timer past an hour and the toggle (Claude's
    /// proposal, AUTHOR'S TAKE NEEDED).
    public static let minimumWidth: Double = 220
    /// Below this, Vertical's first width, the format, the mic's name and the buttons' words drop (Claude's
    /// proposal, AUTHOR'S TAKE NEEDED).
    public static let narrowWidth: Double = 260

    /// Whether the panel is narrow enough to drop the format, the mic's name and the buttons' words.
    public static func isNarrow(width: Double) -> Bool {
        width < narrowWidth
    }

    /// The width the panel opens at the first time: for the preview, Full's (376 pt for Landscape, 260 pt
    /// for Vertical, 497 pt for Both, and Landscape's with no format); for Camera only, 220 pt, a 200 pt
    /// camera as Small had.
    public static func firstWidth(showing shows: RecordingPanelShows, destination: VideoFormat.Destination?) -> Double {
        switch shows {
        case .camera:
            return minimumWidth
        case .preview:
            let height = previewHeight(for: destination)
            let tiles = previewOutputs(for: destination).map { previewTileWidth($0, height: height) }
            return padding * 2 + tiles.reduce(0, +) + spacing * Double(max(0, tiles.count - 1))
        }
    }

    /// The picture's size at a panel width: the preview's tiles filling the content's width, or the camera's
    /// square as wide as it. The width is taken as at least 220 pt.
    public static func pictureSize(width: Double, showing shows: RecordingPanelShows,
                                   destination: VideoFormat.Destination?) -> CGSize {
        let inner = max(minimumWidth, width) - 2 * padding
        switch shows {
        case .camera:
            return CGSize(width: inner, height: inner)
        case .preview:
            return CGSize(width: inner, height: previewTileHeight(contentWidth: inner, destination: destination))
        }
    }

    /// The preview's tiles' height when they fill a content width, 8 pt apart, rounded to the point.
    public static func previewTileHeight(contentWidth: Double, destination: VideoFormat.Destination?) -> Double {
        let outputs = previewOutputs(for: destination)
        let gaps = spacing * Double(max(0, outputs.count - 1))
        return ((contentWidth - gaps) / widthPerHeight(outputs)).rounded()
    }

    /// The panel's size at a width (at least 220 pt): the width, and the picture's height plus the chrome.
    public static func size(width: Double, showing shows: RecordingPanelShows,
                            destination: VideoFormat.Destination?) -> CGSize {
        let width = max(minimumWidth, width)
        return CGSize(width: width, height: chromeHeight + pictureSize(width: width, showing: shows, destination: destination).height)
    }

    /// The width whose panel is `height` tall, so a top or bottom edge drag changes the width to match. Not
    /// limited to the minimum.
    public static func width(forHeight height: Double, showing shows: RecordingPanelShows,
                             destination: VideoFormat.Destination?) -> Double {
        let picture = height - chromeHeight
        switch shows {
        case .camera:
            return picture + 2 * padding
        case .preview:
            let outputs = previewOutputs(for: destination)
            return picture * widthPerHeight(outputs) + spacing * Double(max(0, outputs.count - 1)) + 2 * padding
        }
    }

    /// The widest the panel can be within a display's visible frame: no wider than it, and no taller.
    ///
    /// - Parameter extraHeight: Rows the panel shows beyond its usual chrome, such as a problem line.
    public static func maximumWidth(showing shows: RecordingPanelShows, destination: VideoFormat.Destination?,
                                    within visible: CGSize, extraHeight: Double = 0) -> Double {
        let byHeight = width(forHeight: visible.height - extraHeight, showing: shows, destination: destination)
        return max(minimumWidth, min(visible.width, byHeight).rounded(.down))
    }

    /// A width kept between 220 pt and the most the display's visible frame allows.
    public static func clampedWidth(_ width: Double, showing shows: RecordingPanelShows, destination: VideoFormat.Destination?,
                                    within visible: CGSize, extraHeight: Double = 0) -> Double {
        let most = maximumWidth(showing: shows, destination: destination, within: visible, extraHeight: extraHeight)
        return min(max(minimumWidth, width.rounded()), most)
    }

    // MARK: - The preview's tiles

    /// How tall the setup's preview tiles are, and the preview's the first time: 200 pt, and 427 pt for
    /// Vertical's single Short, so the Short is shown big rather than as a sliver.
    public static func previewHeight(for destination: VideoFormat.Destination?) -> Double {
        destination == .vertical ? 427 : 200
    }

    /// A preview tile's width: its output's shape at the tiles' height.
    public static func previewTileWidth(_ output: OutputShape, height: Double) -> Double {
        (height * Double(output.width) / Double(output.height)).rounded()
    }

    /// The outputs the preview shows: the format's, or a Landscape-sized placeholder when none is chosen.
    public static func previewOutputs(for destination: VideoFormat.Destination?) -> [OutputShape] {
        destination.map { VideoFormat(destination: $0).outputs } ?? [.landscape]
    }

    /// How wide the outputs side by side are per point of height, gaps aside.
    static func widthPerHeight(_ outputs: [OutputShape]) -> Double {
        outputs.map { Double($0.width) / Double($0.height) }.reduce(0, +)
    }
}

/// Resizing the Recording Panel from an edge or corner (docs/ui.md, R6): what it shows keeps its shape, so
/// the width sets the size and the height follows. The edge or corner opposite the one dragged stays put.
public enum RecordingPanelResize {
    /// The edges being dragged: one, or two for a corner.
    public struct Edges: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let left = Edges(rawValue: 1 << 0)
        public static let right = Edges(rawValue: 1 << 1)
        public static let top = Edges(rawValue: 1 << 2)
        public static let bottom = Edges(rawValue: 1 << 3)
    }

    /// The panel's frame after dragging `edges` by `translation`.
    ///
    /// A side sets the width directly. A top or bottom edge sets the height, and the width is the one that
    /// gives it. A corner takes whichever of the two makes the panel bigger. The width stays between
    /// 220 pt and the display's visible frame. Dragging a side keeps the top edge where it was; dragging the
    /// top or bottom keeps the panel's middle; the opposite edge always stays.
    ///
    /// - Parameters:
    ///   - start: The panel's frame when the drag began, in AppKit's global coordinates (y up).
    ///   - translation: How far the pointer has moved since then, y up.
    ///   - extraHeight: Rows the panel shows beyond its usual chrome, such as a problem line.
    ///   - visible: The display's available desktop, which the panel stays inside.
    public static func frame(from start: CGRect, dragging edges: Edges, by translation: CGVector,
                             showing shows: RecordingPanelShows, destination: VideoFormat.Destination?,
                             extraHeight: Double = 0, within visible: CGRect) -> CGRect {
        var proposals: [Double] = []
        if edges.contains(.right) { proposals.append(start.width + translation.dx) }
        if edges.contains(.left) { proposals.append(start.width - translation.dx) }
        let height: Double? = edges.contains(.top) ? start.height + translation.dy
            : edges.contains(.bottom) ? start.height - translation.dy : nil
        if let height {
            proposals.append(RecordingPanelLayout.width(forHeight: height - extraHeight, showing: shows, destination: destination))
        }
        guard let proposed = proposals.max() else { return start }
        // The room on the side that moves, so the edge that stays doesn't get pushed along.
        let roomWidth: Double = if edges.contains(.left) {
            start.maxX - visible.minX
        } else if edges.contains(.right) {
            visible.maxX - start.minX
        } else {
            visible.width
        }
        let roomHeight = edges.contains(.top) ? visible.maxY - start.minY : start.maxY - visible.minY
        let width = RecordingPanelLayout.clampedWidth(proposed, showing: shows, destination: destination,
                                                      within: CGSize(width: roomWidth, height: roomHeight), extraHeight: extraHeight)
        let size = RecordingPanelLayout.size(width: width, showing: shows, destination: destination)
        let newHeight = size.height + extraHeight

        let x: Double = if edges.contains(.left) {
            start.maxX - width
        } else if edges.contains(.right) {
            start.minX
        } else {
            (start.midX - width / 2).rounded()
        }
        let y: Double = edges.contains(.top) ? start.minY : start.maxY - newHeight
        return AreaGeometry.clamped(CGRect(x: x, y: y, width: width, height: newHeight), to: visible)
    }
}

/// What the Recording Panel remembers: whether the floating panel is hidden, and on each display it has
/// been on, what it showed, where it was, and its width for each view, the preview's per format, so it comes
/// back as the creator left it (docs/decisions.md, 50 and 82).
///
/// Places are kept relative to their display's frame, so rearranging displays doesn't lose them.
public struct RecordingPanelMemory: Codable, Equatable, Sendable {
    /// The panel on one display.
    public struct Spot: Codable, Equatable, Sendable {
        /// What it showed last.
        public var shows: RecordingPanelShows
        /// The panel's top left corner, relative to the display's bottom left, in points.
        public var topLeft: CGPoint
        /// The preview's width for each format, by the format's raw value ("landscape", "vertical", "both").
        public var previewWidths: [String: Double]
        /// Camera only's width.
        public var cameraWidth: Double?

        public init(shows: RecordingPanelShows, topLeft: CGPoint, previewWidths: [String: Double] = [:], cameraWidth: Double? = nil) {
            self.shows = shows
            self.topLeft = topLeft
            self.previewWidths = previewWidths
            self.cameraWidth = cameraWidth
        }
    }

    /// Hidden: no floating panel; the menu bar dropdown is its only home (docs/decisions.md, 18).
    public var isHidden: Bool
    /// Each display's spot, by the display's persistent id.
    public var spots: [String: Spot]
    /// The display the panel was last on.
    public var lastDisplay: String?

    public init(isHidden: Bool = false, spots: [String: Spot] = [:], lastDisplay: String? = nil) {
        self.isHidden = isHidden
        self.spots = spots
        self.lastDisplay = lastDisplay
    }

    /// What the panel shows when it opens on a display: what it showed there last, else the preview. With
    /// the camera off, always the preview.
    public func shows(on display: String?, cameraOn: Bool) -> RecordingPanelShows {
        guard cameraOn else { return .preview }
        return display.flatMap { spots[$0]?.shows } ?? .preview
    }

    /// The panel's width on a display for a view: the width it last had there in that view (the preview's
    /// for this format), else the first width.
    public func width(on display: String?, showing shows: RecordingPanelShows, destination: VideoFormat.Destination?) -> Double {
        let spot = display.flatMap { spots[$0] }
        let remembered = switch shows {
        case .camera: spot?.cameraWidth
        case .preview: spot?.previewWidths[Self.key(destination)]
        }
        return remembered ?? RecordingPanelLayout.firstWidth(showing: shows, destination: destination)
    }

    /// Notes what the panel shows, its width for that view, and where it is now.
    ///
    /// - Parameters:
    ///   - frame: The panel's frame, in AppKit's global coordinates. Its width is remembered for `shows`.
    ///   - displayFrame: The frame of the display it's on.
    public mutating func remember(showing shows: RecordingPanelShows, destination: VideoFormat.Destination?,
                                  frame: CGRect, on display: String, displayFrame: CGRect) {
        var spot = spots[display] ?? Spot(shows: shows, topLeft: .zero)
        spot.shows = shows
        spot.topLeft = CGPoint(x: frame.minX - displayFrame.minX, y: frame.maxY - displayFrame.minY)
        switch shows {
        case .camera: spot.cameraWidth = frame.width
        case .preview: spot.previewWidths[Self.key(destination)] = frame.width
        }
        spots[display] = spot
        lastDisplay = display
    }

    /// Where the panel goes on a display it has been on: its remembered top left, with the panel kept
    /// inside the display's available desktop. Nil if it has never been there.
    ///
    /// - Parameters:
    ///   - panelSize: The panel's size now, which may differ from when it was remembered.
    ///   - displayFrame: The display's whole frame, which the spot is relative to.
    ///   - visible: The display's available desktop, which the panel stays inside.
    public func frame(on display: String, panelSize: CGSize, displayFrame: CGRect, visible: CGRect) -> CGRect? {
        guard let spot = spots[display] else { return nil }
        let topLeft = CGPoint(x: displayFrame.minX + spot.topLeft.x, y: displayFrame.minY + spot.topLeft.y)
        let frame = CGRect(x: topLeft.x, y: topLeft.y - panelSize.height, width: panelSize.width, height: panelSize.height)
        return AreaGeometry.clamped(frame, to: visible)
    }

    /// The preview's widths are kept per format; with none chosen, Landscape's, whose shape it shows.
    static func key(_ destination: VideoFormat.Destination?) -> String {
        (destination ?? .landscape).rawValue
    }
}

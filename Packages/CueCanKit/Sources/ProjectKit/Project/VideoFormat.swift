import Foundation

/// Where a video will be posted and its layout: the two choices the setup asks for before a recording
/// (docs/decisions.md, 19 and 89).
///
/// The destination decides which shapes the built-in exports make (docs/decisions.md, 38); the layout decides
/// the shape of the recorded area.
public struct VideoFormat: Codable, Hashable, Sendable {
    /// Where the video will be posted.
    public enum Destination: String, Codable, Sendable, CaseIterable {
        /// YouTube videos: 16:9.
        case landscape
        /// Shorts, Reels and TikTok: 9:16.
        case vertical
        /// A video and a Short from one recording.
        case both
    }

    public var destination: Destination
    /// The layout, one the destination offers (``TakeLayout/isOffered(for:)``).
    public var layout: TakeLayout

    /// A format. A layout the destination doesn't offer gives the destination's standard one.
    public init(destination: Destination, layout: TakeLayout? = nil) {
        self.destination = destination
        if let layout, layout.isOffered(for: destination) {
            self.layout = layout
        } else {
            self.layout = TakeLayout.standard(for: destination)
        }
    }

    /// The format a screen recording starts with: a YouTube video with a card.
    public static let standard = VideoFormat(destination: .landscape)

    /// The shapes the built-in exports make, in the order they're listed.
    public var outputs: [OutputShape] {
        switch destination {
        case .landscape: [.landscape]
        case .vertical: [.vertical]
        case .both: [.landscape, .vertical]
        }
    }

    /// The shape of the area a screen recording captures: the layout's.
    public var captureRatio: CaptureArea.Ratio { layout.captureRatio(for: destination) }

    /// The layout's name, such as "Side by side ⅓" or "Card".
    public var layoutName: String { layout.name(for: destination) }

    /// What the menu bar and the editor show, such as "16:9 & 9:16 · Side by side".
    public var label: String { "\(destinationLabel) · \(layoutName)" }

    /// The output it exports, as the layout menu's title names it: "16:9 video", "9:16 Short", or "16:9 video
    /// and 9:16 Short" (docs/decisions.md, 66).
    public var outputTitle: String {
        switch destination {
        case .landscape: "16:9 video"
        case .vertical: "9:16 Short"
        case .both: "16:9 video and 9:16 Short"
        }
    }

    /// Its shape or shapes alone, such as "16:9 & 9:16" (as asked: in place of Landscape, Vertical and Both).
    public var destinationLabel: String {
        switch destination {
        case .landscape: "16:9"
        case .vertical: "9:16"
        case .both: "16:9 & 9:16"
        }
    }

    /// What a recording of the camera alone shows, such as "16:9 & 9:16 · camera only": with no screen, the layout
    /// means nothing (docs/ui.md, R9).
    public var cameraOnlyLabel: String {
        "\(destinationLabel) · camera only"
    }

    private enum CodingKeys: String, CodingKey { case destination, layout }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let destination = try container.decode(Destination.self, forKey: .destination)
        let layout = try container.decode(TakeLayout.self, forKey: .layout)
        guard layout.isOffered(for: destination) else {
            throw DecodingError.dataCorruptedError(forKey: .layout, in: container,
                                                   debugDescription: "\(destination.rawValue) doesn't offer that layout.")
        }
        self.init(destination: destination, layout: layout)
    }
}

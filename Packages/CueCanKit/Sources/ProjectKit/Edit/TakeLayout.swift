import Foundation

/// What a take is set up for before recording (docs/decisions.md, 89): Side by side, with the shape of the
/// screen recorded, or Card, which always records the whole frame.
///
/// Side by side's shape is the camera's share: the screen fills the video's height (or a Short's width) and
/// the camera takes what's left, so a 4:3 screen leaves it a quarter of a 16:9 video.
public enum TakeLayout: Codable, Hashable, Sendable {
    /// The camera beside the screen, or above or below it in a Short, with no overlap.
    case sideBySide(CaptureArea.Ratio)
    /// The camera as a card over the screen.
    case card(Card)

    /// The screen shapes Side by side offers a format, smallest camera first. Landscape and Vertical offer a
    /// quarter, a third and a half. Both offers the two shapes that keep the screen at least about half of
    /// each output: 9:8 (the camera is 37% of the video and half the Short) and 1:1 (44% of each).
    public static func shares(for destination: VideoFormat.Destination) -> [CaptureArea.Ratio] {
        switch destination {
        case .landscape: [.fourByThree, .thirtyTwoByTwentySeven, .eightByNine]
        case .vertical: [.threeByFour, .twentySevenByThirtyTwo, .nineByEight]
        case .both: [.nineByEight, .square]
        }
    }

    /// What a share is called: "¼", "⅓" or "½" of the video's width or the Short's height; "Wide" or "Square"
    /// for Both, where one shape gives each output a different share.
    public static func shareLabel(_ shape: CaptureArea.Ratio, for destination: VideoFormat.Destination) -> String {
        guard let index = shares(for: destination).firstIndex(of: shape) else { return shape.rawValue }
        return destination == .both ? ["Wide", "Square"][index] : ["¼", "⅓", "½"][index]
    }

    /// Whether a format offers Card. Both doesn't: its one recording is shaped for Side by side.
    public static func offersCard(_ destination: VideoFormat.Destination) -> Bool { destination != .both }

    /// The layout a format starts with: a card, or Side by side for Both (Claude's call).
    public static func standard(for destination: VideoFormat.Destination) -> TakeLayout {
        destination == .both ? .sideBySide(.nineByEight) : .card(Card.standard(for: destination))
    }

    /// The Side by side a format starts with: a third, or Wide for Both.
    public static func standardSideBySide(for destination: VideoFormat.Destination) -> TakeLayout {
        .sideBySide(destination == .both ? .nineByEight : shares(for: destination)[1])
    }

    /// Whether a format offers this layout.
    public func isOffered(for destination: VideoFormat.Destination) -> Bool {
        switch self {
        case .sideBySide(let shape): Self.shares(for: destination).contains(shape)
        case .card(let card): Self.offersCard(destination) && card == card.fitted(to: destination)
        }
    }

    /// The shape of the area a screen recording captures: Side by side's own, or the whole frame for a card.
    public func captureRatio(for destination: VideoFormat.Destination) -> CaptureArea.Ratio {
        switch self {
        case .sideBySide(let shape): shape
        case .card: destination == .vertical ? .nineBySixteen : .sixteenByNine
        }
    }

    /// Whether it's a card.
    public var isCard: Bool { if case .card = self { true } else { false } }

    /// The card, if it is one.
    public var card: Card? { if case .card(let card) = self { card } else { nil } }

    /// The layout a clip of this take starts with.
    public var layout: Layout {
        switch self {
        case .sideBySide: .sideBySide
        case .card(let card): .card(card)
        }
    }

    /// "Side by side ⅓", "Side by side" (for Both) or "Card".
    public func name(for destination: VideoFormat.Destination) -> String {
        switch self {
        case .sideBySide(let shape): destination == .both ? "Side by side" : "Side by side \(Self.shareLabel(shape, for: destination))"
        case .card: "Card"
        }
    }

    // MARK: - Coding

    /// Encoded flat with a `kind`: `{"kind": "sideBySide", "shape": "32:27"}` or
    /// `{"kind": "card", "position": "right", "size": "medium", …}`.
    private enum CodingKeys: String, CodingKey { case kind, shape }
    private enum Kind: String, Codable { case sideBySide, card }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .sideBySide: self = .sideBySide(try container.decode(CaptureArea.Ratio.self, forKey: .shape))
        case .card: self = .card(try Card(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sideBySide(let shape):
            try container.encode(Kind.sideBySide, forKey: .kind)
            try container.encode(shape, forKey: .shape)
        case .card(let card):
            try container.encode(Kind.card, forKey: .kind)
            try card.encode(to: encoder)
        }
    }
}

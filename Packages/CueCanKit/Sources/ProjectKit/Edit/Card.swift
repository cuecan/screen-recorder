import Foundation

/// The camera as a card over the screen (docs/decisions.md, 89; docs/ui/mockups/LayoutsTwoKinds.html): where it
/// sits, how big it is, its shape and roundness, and whether the screen under it is full or smaller. The setup's
/// Layout choices and the editor's Card section set the same five things, so a take starts exactly as set up.
///
/// Nothing is free-form: every card is one of nine places, three sizes and three shapes, so the screen can
/// always make room for it and the area shaded while recording is a card the editor can show.
public struct Card: Codable, Hashable, Sendable {
    /// Where the card sits in the frame: nine places, as a three by three grid.
    public enum Position: String, Codable, Sendable, CaseIterable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

        /// 0, 1 or 2 from the left.
        public var column: Int { (Self.allCases.firstIndex(of: self) ?? 0) % 3 }
        /// 0, 1 or 2 from the top.
        public var row: Int { (Self.allCases.firstIndex(of: self) ?? 0) / 3 }

        /// "Top left", "Centre" and so on.
        public var label: String {
            switch self {
            case .topLeft: "Top left"
            case .top: "Top"
            case .topRight: "Top right"
            case .left: "Left"
            case .center: "Centre"
            case .right: "Right"
            case .bottomLeft: "Bottom left"
            case .bottom: "Bottom"
            case .bottomRight: "Bottom right"
            }
        }
    }

    /// How big the card is.
    public enum Size: String, Codable, Sendable, CaseIterable {
        case small, medium, large

        /// "S", "M" or "L", as the controls show it.
        public var label: String {
            switch self {
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            }
        }
    }

    /// The card's shape. Tall is 3:4 and Wide 16:9 (AUTHOR'S TAKE NEEDED: a Short's Tall is to take FaceTime's
    /// shape and corners once they're measured).
    public enum Shape: String, Codable, Sendable, CaseIterable {
        case square, tall, wide

        public var label: String { rawValue.capitalized }

        /// The roundness a shape starts with: a square is the bubble's squircle, the others a card's corner.
        public var startingRoundness: Double { self == .square ? 0.3 : 0.12 }
    }

    /// How the screen sits under the card.
    public enum Screen: String, Codable, Sendable, CaseIterable {
        /// The screen fills the frame and the card sits over it.
        case full
        /// The screen shrinks until two-thirds of the card is over it and a third hangs off its edge. A 16:9 video only: in a
        /// Short the screen is always full.
        case smaller

        public var label: String { rawValue.capitalized }
    }

    public var position: Position
    public var size: Size
    public var shape: Shape
    public var screen: Screen
    /// The corner radius as a fraction of the card's shorter side, from 0 (square) to 0.5. The corner is
    /// always a continuous one, so 0.3 on a square is the squircle.
    public var roundness: Double { didSet { roundness = Self.roundness(roundness) } }

    /// The range of ``roundness``.
    public static let roundnessRange = 0.0...0.5

    /// A roundness kept in range, to a hundredth.
    public static func roundness(_ value: Double) -> Double {
        guard value.isFinite else { return Shape.tall.startingRoundness }
        return (min(max(value, roundnessRange.lowerBound), roundnessRange.upperBound) * 100).rounded() / 100
    }

    /// A card. With no roundness given, it's the shape's starting one.
    public init(position: Position = .right, size: Size = .medium, shape: Shape = .tall, screen: Screen = .smaller, roundness: Double? = nil) {
        self.position = position
        self.size = size
        self.shape = shape
        self.screen = screen
        self.roundness = Self.roundness(roundness ?? shape.startingRoundness)
    }

    /// The card a 16:9 video starts with: medium and tall on the right, over a smaller screen (Claude's call).
    public static let standard = Card()
    /// The card a Short starts with: a small square bubble in the bottom right, over the whole screen.
    public static let bubble = Card(position: .bottomRight, size: .small, shape: .square, screen: .full)

    /// The card a format starts with.
    public static func standard(for destination: VideoFormat.Destination) -> Card {
        destination == .vertical ? .bubble : .standard
    }

    /// This card in another shape, with that shape's starting roundness.
    public func shaped(_ shape: Shape) -> Card {
        var card = self
        card.shape = shape
        card.roundness = shape.startingRoundness
        return card
    }

    /// This card as a format can record it: a Short's screen is always full.
    public func fitted(to destination: VideoFormat.Destination) -> Card {
        var card = self
        if destination == .vertical { card.screen = .full }
        return card
    }

    /// Such as "Right, M, tall, smaller screen", for a tool's report.
    public var summary: String {
        "\(position.label), \(size.label), \(shape.rawValue), \(screen == .full ? "full screen" : "smaller screen")"
    }
}

import Foundation

/// How a clip fills the frame (docs/decisions.md, 89): Side by side, a card over the screen, or the camera or
/// the screen alone. One layout a clip, drawn for whichever shape is shown (77).
///
/// Encoded flat with a `kind` field, such as `{"kind": "sideBySide"}`, `{"kind": "camera"}` or
/// `{"kind": "card", "position": "right", "size": "medium", "shape": "tall", "screen": "smaller",
/// "roundness": 0.12}`, so Claude can read and write it directly.
public enum Layout: Codable, Hashable, Sendable {
    /// The layout the take was set up for (its source's ``Source/layout``): the camera alone for a take with
    /// no screen, the screen alone for one with no camera.
    case automatic
    /// The camera beside the screen, or above or below it in a Short. Its share is the recording's: the screen
    /// keeps its recorded shape and the camera takes what's left. Only for a take recorded with room beside
    /// the screen.
    case sideBySide
    /// The camera as a card over the screen.
    case card(Card)
    /// The camera filling the frame, edge to edge. The project's inset never applies to it.
    case camera
    /// The screen alone, fitted in the frame.
    case screen

    /// Whether a screen of this shape (width over height) leaves room beside it in an output, which Side by
    /// side needs: narrower than a 16:9 video, or shorter than a 9:16 Short.
    public static func hasRoom(besideScreen aspect: Double, in output: OutputShape) -> Bool {
        let frame = Double(output.width) / Double(output.height)
        return output == .landscape ? aspect < frame * 0.97 : aspect > frame * 1.03
    }

    /// "As recorded", "Side by side", "Card", "Camera" or "Screen". Resolve `automatic` first to name what it
    /// draws.
    public var name: String {
        switch self {
        case .automatic: "As recorded"
        case .sideBySide: "Side by side"
        case .card: "Card"
        case .camera: "Camera"
        case .screen: "Screen"
        }
    }

    /// The name with a card's settings, such as "Card (Right, M, tall, smaller screen)", for a tool's report.
    public var described: String {
        if case .card(let card) = self { "Card (\(card.summary))" } else { name }
    }

    /// The card, if it is one.
    public var card: Card? { if case .card(let card) = self { card } else { nil } }

    private enum CodingKeys: String, CodingKey { case kind }
    private enum Kind: String, Codable { case automatic, sideBySide, card, camera, screen }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .automatic: self = .automatic
        case .sideBySide: self = .sideBySide
        case .card: self = .card(try Card(from: decoder))
        case .camera: self = .camera
        case .screen: self = .screen
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic: try container.encode(Kind.automatic, forKey: .kind)
        case .sideBySide: try container.encode(Kind.sideBySide, forKey: .kind)
        case .camera: try container.encode(Kind.camera, forKey: .kind)
        case .screen: try container.encode(Kind.screen, forKey: .kind)
        case .card(let card):
            try container.encode(Kind.card, forKey: .kind)
            try card.encode(to: encoder)
        }
    }
}

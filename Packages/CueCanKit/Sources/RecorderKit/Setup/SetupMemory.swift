import Foundation
import ProjectKit

/// What a setup remembers between recordings (docs/decisions.md, 78 and 89): the format last used, the layout
/// last picked for each format, and, for each format, the last card and the last Side by side share, so
/// switching between the two kinds brings back what each was set to. A setup opens on them, so a second
/// recording is one shortcut and Return. With nothing remembered, on the first setup ever, no format is chosen.
///
/// The camera, the mic, the screen and their framing are remembered beside it, by the recorder.
public struct SetupMemory: Codable, Equatable, Sendable {
    /// The format last used, or nil before the first.
    public private(set) var destination: VideoFormat.Destination?
    /// The layout last picked for each format.
    public private(set) var layouts: [VideoFormat.Destination: TakeLayout]
    /// The card last set up for each format, whichever kind is picked now.
    public private(set) var cards: [VideoFormat.Destination: Card]
    /// The Side by side shape last picked for each format, whichever kind is picked now.
    public private(set) var shares: [VideoFormat.Destination: CaptureArea.Ratio]

    public init(destination: VideoFormat.Destination? = nil, layouts: [VideoFormat.Destination: TakeLayout] = [:],
                cards: [VideoFormat.Destination: Card] = [:], shares: [VideoFormat.Destination: CaptureArea.Ratio] = [:]) {
        self.destination = destination
        self.layouts = layouts.filter { $0.value.isOffered(for: $0.key) }
        self.cards = cards.filter { TakeLayout.card($0.value).isOffered(for: $0.key) }
        self.shares = shares.filter { TakeLayout.sideBySide($0.value).isOffered(for: $0.key) }
    }

    /// The format a setup opens on: the last one used, with its layout, or nil before the first.
    public var format: VideoFormat? {
        destination.map { VideoFormat(destination: $0, layout: layouts[$0]) }
    }

    /// The layout a format starts with: the one last picked for it, or its standard one.
    public func layout(for destination: VideoFormat.Destination) -> TakeLayout {
        layouts[destination] ?? TakeLayout.standard(for: destination)
    }

    /// The card a format's Card choice starts with: the last one set up for it, or its standard one.
    public func card(for destination: VideoFormat.Destination) -> Card {
        cards[destination] ?? Card.standard(for: destination)
    }

    /// The Side by side a format's choice starts with: the share last picked for it, or its standard one.
    public func sideBySide(for destination: VideoFormat.Destination) -> TakeLayout {
        shares[destination].map(TakeLayout.sideBySide) ?? TakeLayout.standardSideBySide(for: destination)
    }

    /// A format was picked.
    public mutating func use(_ destination: VideoFormat.Destination) {
        self.destination = destination
    }

    /// A layout was picked for a format. One the format doesn't offer is ignored.
    public mutating func use(_ layout: TakeLayout, for destination: VideoFormat.Destination) {
        guard layout.isOffered(for: destination) else { return }
        layouts[destination] = layout
        switch layout {
        case .card(let card): cards[destination] = card
        case .sideBySide(let shape): shares[destination] = shape
        }
    }

    // MARK: - Coding

    /// Encoded with the formats by name: `{"destination": "both", "layouts": {"both": {…}}, "cards": {…},
    /// "shares": {…}}`.
    private enum CodingKeys: String, CodingKey { case destination, layouts, cards, shares }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func byFormat<Value: Decodable>(_ key: CodingKeys) throws -> [VideoFormat.Destination: Value] {
            var values: [VideoFormat.Destination: Value] = [:]
            for (name, value) in try container.decode([String: Value].self, forKey: key) {
                guard let destination = VideoFormat.Destination(rawValue: name) else {
                    throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "There's no format called “\(name)”.")
                }
                values[destination] = value
            }
            return values
        }
        self.init(destination: try container.decodeIfPresent(VideoFormat.Destination.self, forKey: .destination),
                  layouts: try byFormat(.layouts), cards: try byFormat(.cards), shares: try byFormat(.shares))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(destination, forKey: .destination)
        func byName<Value>(_ values: [VideoFormat.Destination: Value]) -> [String: Value] {
            Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        }
        try container.encode(byName(layouts), forKey: .layouts)
        try container.encode(byName(cards), forKey: .cards)
        try container.encode(byName(shares), forKey: .shares)
    }
}

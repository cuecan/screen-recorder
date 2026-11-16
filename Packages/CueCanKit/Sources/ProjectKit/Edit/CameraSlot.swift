import Foundation

/// A kind of camera slot in the layouts, each framed on its own (docs/decisions.md, 52; docs/ui.md, R8):
/// framing the card never changes the large camera, and the other way round.
public enum CameraSlot: String, Codable, Sendable, CaseIterable {
    /// The card over the screen, whatever its size and shape (docs/decisions.md, 89).
    case card
    /// Side by side's camera: beside the screen in the 16:9 video, above or below it in the 9:16 Short. One framing
    /// for both, outlined as the shape shown crops it (docs/decisions.md, 77).
    case split
    /// The camera filling the frame. Until it's framed, it starts from Side by side's framing.
    case fullScreen

    /// What the framing popover's tabs and the tool's report call it.
    public var label: String {
        switch self {
        case .card: "Card"
        case .split: "Side by side"
        case .fullScreen: "Full screen"
        }
    }

    /// Side by side's camera slot, which a full-screen camera starts from.
    public static let large = CameraSlot.split
}

/// How one camera is framed in each kind of slot: a point and a zoom per slot (docs/decisions.md, 52).
///
/// A slot that isn't framed is centred and not zoomed, except the full-screen camera, which starts from
/// Side by side's framing. A framing is the same in both shapes; each crops its own slot around it.
public struct CameraFramings: Codable, Equatable, Sendable {
    /// The slots that have been framed.
    public private(set) var slots: [CameraSlot: CameraFraming]

    public init(_ slots: [CameraSlot: CameraFraming] = [:]) {
        self.slots = slots
    }

    /// The same framing in every slot, as `set_camera_framing` gives when no slot is named.
    public static func everywhere(_ framing: CameraFraming) -> Self {
        Self(Dictionary(uniqueKeysWithValues: CameraSlot.allCases.map { ($0, framing) }))
    }

    /// No slot is framed.
    public var isEmpty: Bool { slots.isEmpty }

    /// The framing a slot has been given, if any.
    public subscript(slot: CameraSlot) -> CameraFraming? {
        get { slots[slot] }
        set { slots[slot] = newValue }
    }

    /// The framing a slot shows.
    public func framing(for slot: CameraSlot) -> CameraFraming {
        if let framing = slots[slot] { return framing }
        if slot == .fullScreen, let large = slots[CameraSlot.large] { return large }
        return .centered
    }

    /// These framings, with every slot they don't frame starting from `framing`, such as the creator's face
    /// found while setting up (docs/decisions.md, 78). A framing given by hand always wins. The full-screen
    /// camera is left to follow the large camera, as it does when it isn't framed.
    public func filling(with framing: CameraFraming) -> CameraFramings {
        var filled = self
        for slot in CameraSlot.allCases where slot != .fullScreen && filled[slot] == nil {
            filled[slot] = framing
        }
        return filled
    }

    /// These framings, with every slot `other` frames taking its framing.
    public func merging(_ other: CameraFramings) -> CameraFramings {
        CameraFramings(slots.merging(other.slots) { _, new in new })
    }

    // MARK: - Coding

    /// Encoded as an object by slot name, such as `{"card": {"centerX": 0.5, …}}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SlotKey.self)
        for slot in CameraSlot.allCases {
            if let framing = slots[slot] { try container.encode(framing, forKey: SlotKey(slot.rawValue)) }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: SlotKey.self)
        var slots: [CameraSlot: CameraFraming] = [:]
        for key in container.allKeys {
            guard let slot = CameraSlot(rawValue: key.stringValue) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "There's no camera slot called “\(key.stringValue)”.")
            }
            slots[slot] = try container.decode(CameraFraming.self, forKey: key)
        }
        self.slots = slots
    }

    private struct SlotKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

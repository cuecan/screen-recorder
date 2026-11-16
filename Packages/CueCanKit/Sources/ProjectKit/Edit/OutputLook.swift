import Foundation

/// The look a frame is drawn with, in either shape: the clip's camera side (``ClipLook``), with the inset,
/// rounded corners, background and mirroring every clip shares (``EditLook``) (docs/decisions.md, 61, 66, 68
/// and 77). Nothing stores it whole: ``Edit/look(of:)`` puts it together.
public struct OutputLook: Codable, Equatable, Sendable {
    /// The space around and between the tiles, as a fraction of the output's short side, so it's the same in
    /// the video and the Short and whole pixels at 720p, 1080p and 4K (docs/decisions.md, 66).
    public enum Inset: String, Codable, Sendable, CaseIterable {
        /// Edge to edge.
        case none
        /// 1/36: 30 px at 1080p.
        case small
        /// 1/18: 60 px at 1080p.
        case medium
        /// 1/12: 90 px at 1080p.
        case large

        /// The inset as a fraction of the output's short side.
        public var fraction: Double {
            switch self {
            case .none: 0
            case .small: 1.0 / 36
            case .medium: 1.0 / 18
            case .large: 1.0 / 12
            }
        }

        /// "None", "S", "M" or "L", as the editor shows it.
        public var label: String {
            switch self {
            case .none: "None"
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            }
        }
    }

    /// Which side Side by side's camera is on. Standard is right of the screen in the video and above it in the
    /// Short; flipped is the other side. A card has its own position.
    public enum CameraSide: String, Codable, Sendable, CaseIterable {
        case standard
        case flipped

        /// The side's one word in an output: "Right" or "Left" in the video, "Above" or "Below" in the Short.
        public func label(in output: OutputShape) -> String {
            switch output {
            case .landscape: self == .standard ? "Right" : "Left"
            case .vertical: self == .standard ? "Above" : "Below"
            }
        }

        /// The other side.
        public var toggled: CameraSide { self == .standard ? .flipped : .standard }

        /// The side a name means in an output: right or left in the video, above or below in the Short;
        /// "standard" and "flipped" anywhere.
        public init?(name: String, in output: OutputShape) {
            let name = name.lowercased()
            if let side = CameraSide(rawValue: name) {
                self = side
                return
            }
            guard let side = CameraSide.allCases.first(where: { $0.label(in: output).lowercased() == name }) else { return nil }
            self = side
        }
    }

    /// The base look behind the tiles: the look's plain colour, or one of five fixed looks, three on white and
    /// two on near-black (a spike: docs/decisions.md, 81). A base look has no settings: it
    /// brings its own background and at most one slow motion. What's added to it is an ``AddOn``.
    public enum Backdrop: String, Codable, Sendable, CaseIterable {
        /// The look's one plain colour.
        case plain
        /// White, still.
        case paper
        /// White, the light drifting: a faint warm band crosses behind the tiles, and shadows swing with it.
        case daylight
        /// White, with a pale bloom of the camera's own colours behind the tiles, slowly breathing.
        case aura
        /// Near-black, still.
        case ink
        /// Near-black, with a deeper bloom of the camera's own colours, slowly breathing.
        case glow

        /// "Plain", "Paper" and so on, as the editor shows it.
        public var label: String { rawValue.capitalized }

        /// Whether it's one of the fixed looks, with its own background.
        public var isPreset: Bool { self != .plain }

        /// Whether the look is on near-black. False for the plain colour.
        public var isDark: Bool { self == .ink || self == .glow }

        /// The look's own background, as `#RRGGBB`; nil for the plain colour, which is the look's.
        public var background: String? {
            guard isPreset else { return nil }
            return isDark ? "#0D0E10" : "#FFFFFF"
        }
    }

    /// What's added to any look, each switched on or off by itself: both are on to start with. The spike
    /// tried five more (a light source, a vignette, grain, a glass panel and a travelling light); only these were kept:
    /// these two (docs/decisions.md, 81).
    public enum AddOn: String, Codable, Sendable, CaseIterable, Comparable {
        /// Two soft shadows under every tile.
        case shadows
        /// A hairline around every tile, brighter along its top.
        case litEdge

        /// "Shadows" or "Lit edge", as the editor shows it.
        public var label: String {
            switch self {
            case .shadows: "Shadows"
            case .litEdge: "Lit edge"
            }
        }

        public static func < (a: AddOn, b: AddOn) -> Bool {
            (allCases.firstIndex(of: a) ?? 0) < (allCases.firstIndex(of: b) ?? 0)
        }

        /// What a look starts with: both.
        public static let starting: Set<AddOn> = [.shadows, .litEdge]
    }

    public var inset: Inset
    /// On, corners are four-fifths of the inset; with no inset, a corner stays square where it meets the
    /// frame's edge or another tile. Off, every tile's corner is square; a card keeps its own roundness.
    public var rounded: Bool
    /// The plain colour behind everything, as `#RRGGBB`. No gradients or images (docs/decisions.md, 3).
    public var background: String { didSet { background = Self.normalizedColor(background) ?? oldValue } }
    /// The base look behind the tiles: the plain colour, or one of the fixed looks (a spike:
    /// docs/decisions.md, 81). Written only when it isn't plain.
    public var backdrop: Backdrop
    /// What's added to the look (81): shadows and a lit edge, both on to start with. Written only when there's
    /// something, so a file without it has neither.
    public var addOns: Set<AddOn>
    public var cameraSide: CameraSide
    /// Flips the camera's picture left to right, so the creator faces what they're showing.
    public var mirror: Bool

    /// The look a first take starts with: Inset M, rounded, on black, with shadows and a lit edge, the camera on its standard side and not
    /// mirrored (Claude's call). Later takes start with the last take's look (docs/decisions.md, 66 and 68).
    public static let plain = OutputLook()

    public init(inset: Inset = .medium, rounded: Bool = true, background: String = "#000000", backdrop: Backdrop = .plain, addOns: Set<AddOn> = AddOn.starting, cameraSide: CameraSide = .standard, mirror: Bool = false) {
        self.inset = inset
        self.rounded = rounded
        self.background = Self.normalizedColor(background) ?? "#000000"
        self.backdrop = backdrop
        self.addOns = addOns
        self.cameraSide = cameraSide
        self.mirror = mirror
    }

    /// The colour that's really behind the tiles: a base look's own, else the plain colour.
    public var shownBackground: String { backdrop.background ?? background }

    /// The shown background's red, green and blue, from 0 to 1.
    public var backgroundComponents: (red: Double, green: Double, blue: Double) {
        let value = Int(shownBackground.dropFirst(), radix: 16) ?? 0
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// `#rgb`, `#rrggbb` or `rrggbb`, as `#RRGGBB`; nil for anything else.
    public static func normalizedColor(_ text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespaces).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + hex
    }

    private enum CodingKeys: String, CodingKey { case inset, rounded, background, backdrop, addOns, cameraSide, mirror }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let color = try container.decode(String.self, forKey: .background)
        guard Self.normalizedColor(color) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .background, in: container, debugDescription: "A background is a colour like #1E1E20, not “\(color)”.")
        }
        self.init(
            inset: try container.decode(Inset.self, forKey: .inset),
            rounded: try container.decode(Bool.self, forKey: .rounded),
            background: color,
            backdrop: try container.decodeIfPresent(Backdrop.self, forKey: .backdrop) ?? .plain,
            addOns: Set(try container.decodeIfPresent([AddOn].self, forKey: .addOns) ?? []),
            cameraSide: try container.decode(CameraSide.self, forKey: .cameraSide),
            mirror: try container.decode(Bool.self, forKey: .mirror)
        )
    }

    /// `backdrop` and `addOns` are written only when they're set.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inset, forKey: .inset)
        try container.encode(rounded, forKey: .rounded)
        try container.encode(background, forKey: .background)
        if backdrop != .plain { try container.encode(backdrop, forKey: .backdrop) }
        if !addOns.isEmpty { try container.encode(addOns.sorted(), forKey: .addOns) }
        try container.encode(cameraSide, forKey: .cameraSide)
        try container.encode(mirror, forKey: .mirror)
    }
}

extension OutputLook {
    /// A clip's look over what the edit shares.
    public init(_ shared: EditLook, _ clip: ClipLook) {
        self.init(inset: shared.inset, rounded: shared.rounded, background: shared.background, backdrop: shared.backdrop, addOns: shared.addOns, cameraSide: clip.cameraSide, mirror: shared.mirror)
    }

    /// The part every clip shares.
    public var shared: EditLook { EditLook(inset: inset, rounded: rounded, background: background, backdrop: backdrop, addOns: addOns, mirror: mirror) }

    /// The part each clip sets for itself.
    public var clip: ClipLook { ClipLook(cameraSide: cameraSide) }
}

/// What a clip sets for itself, the same in both shapes: which side its camera is on (docs/decisions.md, 68 and 77). A split copies it, so every piece of a clip keeps it. The inset was a
/// clip's own at first; it's the edit's now (86).
public struct ClipLook: Codable, Hashable, Sendable {
    public var cameraSide: OutputLook.CameraSide
    /// Whether this clip shows animated captions (a spike: docs/decisions.md, 80). Like the
    /// camera side, a split copies it into each piece and a clip added later takes the one before's. Written only
    /// when on.
    public var captions: Bool

    /// The camera on its standard side, no captions, as a first take starts (Claude's call).
    public init(cameraSide: OutputLook.CameraSide = .standard, captions: Bool = false) {
        self.cameraSide = cameraSide
        self.captions = captions
    }

    private enum CodingKeys: String, CodingKey { case cameraSide, captions }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cameraSide = try container.decode(OutputLook.CameraSide.self, forKey: .cameraSide)
        captions = try container.decodeIfPresent(Bool.self, forKey: .captions) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cameraSide, forKey: .cameraSide)
        if captions { try container.encode(true, forKey: .captions) }
    }
}

/// What every clip shares, in both shapes: the inset, rounded corners or not, the background and what's added
/// to it, and whether the camera is mirrored. These belong to the video and its creator, not to a shot.
public struct EditLook: Codable, Equatable, Sendable {
    /// The space around and between the tiles, the same in every clip, so the base look's shadows and glass
    /// never change size at a cut (docs/decisions.md, 86).
    public var inset: OutputLook.Inset
    /// On, corners are four-fifths of the inset; with no inset, a corner stays square where it meets the
    /// frame's edge or another tile. Off, every tile's corner is square; a card keeps its own roundness.
    public var rounded: Bool
    /// The plain colour behind everything, as `#RRGGBB`. No gradients or images (docs/decisions.md, 3).
    public var background: String { didSet { background = OutputLook.normalizedColor(background) ?? oldValue } }
    /// The base look behind the tiles: the plain colour, or one of the fixed looks (a spike:
    /// docs/decisions.md, 81). Written only when it isn't plain.
    public var backdrop: OutputLook.Backdrop
    /// What's added to the look (81): shadows and a lit edge, both on to start with. Written only when there's
    /// something, so a file without it has neither.
    public var addOns: Set<OutputLook.AddOn>
    /// Flips the camera's picture left to right, so the creator faces what they're showing.
    public var mirror: Bool

    /// Inset M, rounded, on black, with shadows and a lit edge, not mirrored, as a first take starts.
    public init(inset: OutputLook.Inset = .medium, rounded: Bool = true, background: String = "#000000", backdrop: OutputLook.Backdrop = .plain, addOns: Set<OutputLook.AddOn> = OutputLook.AddOn.starting, mirror: Bool = false) {
        self.inset = inset
        self.rounded = rounded
        self.background = OutputLook.normalizedColor(background) ?? "#000000"
        self.backdrop = backdrop
        self.addOns = addOns
        self.mirror = mirror
    }

    private enum CodingKeys: String, CodingKey { case inset, rounded, background, backdrop, addOns, mirror }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let color = try container.decode(String.self, forKey: .background)
        guard OutputLook.normalizedColor(color) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .background, in: container, debugDescription: "A background is a colour like #1E1E20, not “\(color)”.")
        }
        self.init(inset: try container.decode(OutputLook.Inset.self, forKey: .inset),
                  rounded: try container.decode(Bool.self, forKey: .rounded), background: color,
                  backdrop: try container.decodeIfPresent(OutputLook.Backdrop.self, forKey: .backdrop) ?? .plain,
                  addOns: Set(try container.decodeIfPresent([OutputLook.AddOn].self, forKey: .addOns) ?? []),
                  mirror: try container.decode(Bool.self, forKey: .mirror))
    }

    /// Whether the inset, the corners and Mirror are as a first take starts: what the editor's Appearance
    /// section resets.
    public var hasStartingAppearance: Bool {
        let start = EditLook()
        return inset == start.inset && rounded == start.rounded && mirror == start.mirror
    }

    /// Puts the inset, the corners and Mirror back as a first take starts, leaving the background.
    public mutating func resetAppearance() {
        let start = EditLook()
        inset = start.inset
        rounded = start.rounded
        mirror = start.mirror
    }

    /// Whether the colour, the base look and the add-ons are as a first take starts: what the editor's
    /// Background section resets.
    public var hasStartingBackground: Bool {
        let start = EditLook()
        return background == start.background && backdrop == start.backdrop && addOns == start.addOns
    }

    /// Puts the colour, the base look and the add-ons back as a first take starts, leaving the rest.
    public mutating func resetBackground() {
        let start = EditLook()
        background = start.background
        backdrop = start.backdrop
        addOns = start.addOns
    }

    /// Chooses a base look, leaving the add-ons as they are.
    public mutating func choose(_ backdrop: OutputLook.Backdrop) {
        self.backdrop = backdrop
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inset, forKey: .inset)
        try container.encode(rounded, forKey: .rounded)
        try container.encode(background, forKey: .background)
        if backdrop != .plain { try container.encode(backdrop, forKey: .backdrop) }
        if !addOns.isEmpty { try container.encode(addOns.sorted(), forKey: .addOns) }
        try container.encode(mirror, forKey: .mirror)
    }
}

/// One value for each shape: the 16:9 video's and the 9:16 Short's. For what's worked out per shape, such as a
/// caption style's sizes; no setting in the edit is kept this way (docs/decisions.md, 77).
public struct PerOutput<Value> {
    public var landscape: Value
    public var vertical: Value

    public init(landscape: Value, vertical: Value) {
        self.landscape = landscape
        self.vertical = vertical
    }

    /// The same value in both.
    public init(_ both: Value) {
        self.init(landscape: both, vertical: both)
    }

    public subscript(output: OutputShape) -> Value {
        get { output == .landscape ? landscape : vertical }
        set { if output == .landscape { landscape = newValue } else { vertical = newValue } }
    }
}

extension PerOutput: Equatable where Value: Equatable {}
extension PerOutput: Hashable where Value: Hashable {}
extension PerOutput: Sendable where Value: Sendable {}
extension PerOutput: Codable where Value: Codable {}

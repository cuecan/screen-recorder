import Foundation

/// Animated captions in `edit.json` (docs/decisions.md, 80): one style and one timing for the edit, plus the
/// words emphasised and where lines break, by word id. Whether a clip shows them is the clip's own
/// (``ClipLook/captions``), with the same rules as its camera side: a split copies it, and several clips change
/// together.
///
/// Nothing here is set once for the video and again for the Short (docs/decisions.md, 77). A style carries its
/// own values for each shape, since the Short's frame is narrower, and they're always chosen and changed
/// together; captions are laid out again for whichever shape is drawn.
///
/// They're never a rendered video: the compositor draws them from the transcript with the fixes laid over it,
/// through every cut, speed change and freeze, so they're a function of the edit and the time, and a cut or a
/// word fix moves them for free.
public struct Captions: Codable, Equatable, Sendable {
    /// How captions look and when words show, as one shape draws them.
    public struct Setting: Equatable, Sendable {
        public var style: CaptionStyle
        public var timing: CaptionTiming

        public init(style: CaptionStyle, timing: CaptionTiming = CaptionTiming()) {
            self.style = style
            self.timing = timing
        }
    }

    /// The one style, as each shape draws it: the whole style, not a name, so a value can be tried without
    /// new code. Set both together, with ``setStyle(named:)`` or ``changeStyle(with:)``.
    public private(set) var style: PerOutput<CaptionStyle>
    public var timing: CaptionTiming
    /// Words drawn emphasised, in id order.
    public var emphasis: [WordID]
    /// Words that start a new line, in id order.
    public var lineBreaks: [WordID]

    public init(timing: CaptionTiming = CaptionTiming(), emphasis: [WordID] = [], lineBreaks: [WordID] = []) {
        self.style = Self.standard
        self.timing = timing
        self.emphasis = emphasis
        self.lineBreaks = lineBreaks
    }

    /// The catalog's first style, as each shape draws it.
    public static var standard: PerOutput<CaptionStyle> {
        PerOutput(landscape: .pop(for: .landscape), vertical: .pop(for: .vertical))
    }

    /// The style and timing as one shape draws them.
    public subscript(output: OutputShape) -> Setting {
        Setting(style: style[output], timing: timing)
    }

    /// The style's name.
    public var styleName: String { style.landscape.name }

    /// Chooses a catalog style by name, ignoring case. False when there's no such style.
    @discardableResult
    public mutating func setStyle(named name: String) -> Bool {
        guard let landscape = CaptionStyle.named(name, for: .landscape), let vertical = CaptionStyle.named(name, for: .vertical) else { return false }
        style = PerOutput(landscape: landscape, vertical: vertical)
        return true
    }

    /// Changes some of the style's values, in both shapes alike (``CaptionStyle/changing(with:)``).
    public mutating func changeStyle(with changes: Data) throws {
        style = PerOutput(landscape: try style.landscape.changing(with: changes), vertical: try style.vertical.changing(with: changes))
    }

    /// Adds words to the emphasis, or takes them out.
    public mutating func setEmphasis(_ words: some Sequence<WordID>, on: Bool) {
        emphasis = Self.updated(emphasis, words, on: on)
    }

    /// Makes these words start a line, or not.
    public mutating func setLineBreaks(before words: some Sequence<WordID>, on: Bool) {
        lineBreaks = Self.updated(lineBreaks, words, on: on)
    }

    private static func updated(_ list: [WordID], _ words: some Sequence<WordID>, on: Bool) -> [WordID] {
        var set = Set(list)
        if on { set.formUnion(words) } else { set.subtract(words) }
        return set.sorted { $0.number < $1.number }
    }
}

/// When caption words are shown, against the transcript's times (docs/design.md, "Captions").
///
/// A word is shown when the transcript says it starts. Those starts come from the timing model and are kept
/// out of silences when a take is transcribed (docs/decisions.md, 95), so captions no longer look for a
/// word's sound themselves: the "Start words on their sound" option, which did that from the levels for
/// words after a pause and could land on a consonant's closure, is gone.
public struct CaptionTiming: Codable, Equatable, Sendable {
    /// Shows every word this much earlier, in seconds. Negative shows them later.
    public var lead: TimeInterval

    public init(lead: TimeInterval = 0) {
        self.lead = lead
    }
}

extension Edit {
    /// Whether any clip shows captions.
    public var showsCaptions: Bool { main.contains { $0.look.captions } }

    /// Turns captions on or off for these clips, or for every clip when `clips` is nil.
    public mutating func setCaptions(_ on: Bool, for clips: Set<ClipID>? = nil) {
        for index in main.indices where clips?.contains(main[index].id) ?? true {
            main[index].look.captions = on
        }
    }
}

import Foundation

/// How animated captions look and move, as data (docs/decisions.md, 80). The renderer has one way of drawing
/// and reads everything from here, so a new style is a new value and never new code: five styles are five
/// values in ``catalog(for:)``.
///
/// Sizes are fractions of the output's shorter side and times are seconds, so a style reads the same at 1080p
/// and 4K. Every number in the catalog is a starting value, to judge by eye (AUTHOR'S TAKE NEEDED).
public struct CaptionStyle: Codable, Equatable, Sendable {
    /// Which words are on screen together.
    public struct Words: Codable, Equatable, Sendable {
        /// The most words on screen at once.
        public var atOnce: Int
        /// A page breaks before it gets longer than this many characters, spaces included.
        public var characters: Int
        /// The most lines a page wraps onto. A forced break past this starts a new page.
        public var lines: Int
        /// The widest a line may be, as a fraction of the output's width.
        public var width: Double
        public var uppercase: Bool
        /// Whether commas and full stops are drawn. Question and exclamation marks always are.
        public var keepsPunctuation: Bool

        public init(atOnce: Int, characters: Int, lines: Int, width: Double, uppercase: Bool, keepsPunctuation: Bool) {
            self.atOnce = atOnce
            self.characters = characters
            self.lines = lines
            self.width = width
            self.uppercase = uppercase
            self.keepsPunctuation = keepsPunctuation
        }
    }

    /// The letters themselves.
    public struct Lettering: Codable, Equatable, Sendable {
        /// A font's PostScript name, from the fonts macOS ships. A name that isn't installed draws in the
        /// system font's heaviest weight.
        public var font: String
        /// The text's size, as a fraction of the output's shorter side.
        public var size: Double
        /// From one line's baseline to the next, as a multiple of the size.
        public var lineSpacing: Double
        /// The gap between words, as a multiple of the size, outlines aside.
        public var wordSpacing: Double
        /// `#RRGGBB`.
        public var fill: String
        /// An outline drawn outside the letters, or none.
        public var stroke: Stroke?
        /// A soft shadow under the letters, or none.
        public var shadow: Shadow?

        public init(font: String, size: Double, lineSpacing: Double, wordSpacing: Double, fill: String, stroke: Stroke?, shadow: Shadow?) {
            self.font = font
            self.size = size
            self.lineSpacing = lineSpacing
            self.wordSpacing = wordSpacing
            self.fill = fill
            self.stroke = stroke
            self.shadow = shadow
        }
    }

    public struct Stroke: Codable, Equatable, Sendable {
        /// As a fraction of the text size.
        public var width: Double
        public var color: String

        public init(width: Double, color: String) {
            self.width = width
            self.color = color
        }
    }

    public struct Shadow: Codable, Equatable, Sendable {
        public var color: String
        public var opacity: Double
        /// As a fraction of the text size.
        public var blur: Double
        /// How far down, as a fraction of the text size.
        public var drop: Double

        public init(color: String, opacity: Double, blur: Double, drop: Double) {
            self.color = color
            self.opacity = opacity
            self.blur = blur
            self.drop = drop
        }
    }

    /// How the word being said is marked.
    public struct Spoken: Codable, Equatable, Sendable {
        public enum Reach: String, Codable, Sendable, CaseIterable {
            /// Nothing marks it.
            case none
            /// Only the word being said.
            case word
            /// The word being said and every word before it on the page, karaoke-like.
            case throughWord
        }

        public var reach: Reach
        /// The marked word's colour, or nil to keep the fill.
        public var fill: String?
        /// A rounded box behind the marked word, gliding from word to word, or none.
        public var box: Box?
        /// How much bigger the word being said is drawn. It springs up to this when its turn starts and back
        /// when it ends; 1 doesn't move.
        public var scale: Double

        public init(reach: Reach, fill: String?, box: Box?, scale: Double) {
            self.reach = reach
            self.fill = fill
            self.box = box
            self.scale = scale
        }
    }

    public struct Box: Codable, Equatable, Sendable {
        public var color: String
        public var opacity: Double
        /// Around the word, as a fraction of the text size.
        public var padding: Double
        /// As a fraction of the text size.
        public var corner: Double

        public init(color: String, opacity: Double, padding: Double, corner: Double) {
            self.color = color
            self.opacity = opacity
            self.padding = padding
            self.corner = corner
        }
    }

    /// How words come in.
    public struct Entrance: Codable, Equatable, Sendable {
        public enum Reveal: String, Codable, Sendable, CaseIterable {
            /// The page's words all come in when its first word is said.
            case page
            /// Each word comes in when it's said.
            case word
        }

        public enum Motion: String, Codable, Sendable, CaseIterable {
            /// There at once.
            case none
            /// Fades in.
            case fade
            /// Fades in and springs up from smaller.
            case pop
            /// Fades in while rising.
            case rise
        }

        public var reveal: Reveal
        public var motion: Motion
        /// How long the fade in takes.
        public var duration: TimeInterval
        /// How long a page takes to fade out, ending when it ends.
        public var exit: TimeInterval

        public init(reveal: Reveal, motion: Motion, duration: TimeInterval, exit: TimeInterval) {
            self.reveal = reveal
            self.motion = motion
            self.duration = duration
            self.exit = exit
        }
    }

    /// The spring every scale moves on: how long one swing takes, and how quickly it settles (0 never does,
    /// 1 doesn't overshoot).
    public struct Spring: Codable, Equatable, Sendable {
        public var period: TimeInterval
        public var damping: Double

        public init(period: TimeInterval, damping: Double) {
            self.period = period
            self.damping = damping
        }
    }

    /// How a word the creator or Claude emphasised is drawn.
    public struct Emphasis: Codable, Equatable, Sendable {
        /// Its colour, or nil to keep the fill.
        public var fill: String?
        public var scale: Double

        public init(fill: String?, scale: Double) {
            self.fill = fill
            self.scale = scale
        }
    }

    /// Where a page sits in the frame.
    public enum Position: String, Codable, Sendable, CaseIterable {
        /// In the layout's free room: the band between or around the pictures when one is tall enough, the
        /// seam between a stacked screen and camera, else low over the screen and clear of the camera.
        case free
        case bottom
        case middle
        case top
    }

    public var name: String
    public var words: Words
    public var lettering: Lettering
    public var spoken: Spoken
    public var entrance: Entrance
    public var spring: Spring
    public var emphasis: Emphasis
    public var position: Position
    /// Moves the page down from where its position puts it, as a fraction of the output's height.
    public var offset: Double

    public init(name: String, words: Words, lettering: Lettering, spoken: Spoken, entrance: Entrance, spring: Spring, emphasis: Emphasis,
                position: Position, offset: Double) {
        self.name = name
        self.words = words
        self.lettering = lettering
        self.spoken = spoken
        self.entrance = entrance
        self.spring = spring
        self.emphasis = emphasis
        self.position = position
        self.offset = offset
    }

    /// Every colour the style names.
    public var colors: [String] {
        [lettering.fill, lettering.stroke?.color, lettering.shadow?.color, spoken.fill, spoken.box?.color, emphasis.fill].compactMap { $0 }
    }

    /// Why the style can't be drawn, in words, or nil when it can.
    public var problem: String? {
        if let bad = colors.first(where: { OutputLook.normalizedColor($0) == nil }) { return "“\(bad)” isn't a colour like #FFD60A." }
        if words.atOnce < 1 || words.characters < 1 || words.lines < 1 { return "words.atOnce, words.characters and words.lines must be at least 1." }
        if !(0.1...1).contains(words.width) { return "words.width is a fraction of the output's width, from 0.1 to 1." }
        if !(0.005...0.3).contains(lettering.size) { return "lettering.size is a fraction of the output's shorter side, from 0.005 to 0.3." }
        if lettering.lineSpacing <= 0 || lettering.wordSpacing < 0 { return "Line spacing must be above 0 and word spacing can't be negative." }
        if let stroke = lettering.stroke, stroke.width < 0 { return "The outline's width can't be negative." }
        if let shadow = lettering.shadow {
            if !(0...1).contains(shadow.opacity) { return "Shadow opacity must be from 0 to 1." }
            if shadow.blur < 0 || shadow.drop < 0 { return "Shadow blur and drop can't be negative." }
        }
        if let box = spoken.box {
            if !(0...1).contains(box.opacity) { return "Box opacity must be from 0 to 1." }
            if box.padding < 0 || box.corner < 0 { return "Box padding and corner radius can't be negative." }
        }
        if spoken.scale <= 0 || emphasis.scale <= 0 { return "Scales must be above 0." }
        if spring.period <= 0 || !(0...1).contains(spring.damping) { return "spring.period must be above 0 and spring.damping from 0 to 1." }
        if entrance.duration < 0 || entrance.exit < 0 { return "Entrance times can't be negative." }
        return nil
    }

    /// The largest a word is ever drawn, as a multiple of the size, so its letters are drawn once at that
    /// size and only ever scaled down.
    public var largestScale: Double {
        let entering = entrance.motion == .pop ? 1 + CaptionMotion.overshoot(damping: spring.damping) * (1 - CaptionMotion.popFrom) : 1
        let spokenPeak = 1 + (spoken.scale - 1) * (1 + CaptionMotion.overshoot(damping: spring.damping))
        return max(1, emphasis.scale) * max(1, spokenPeak) * entering
    }
}

extension CaptionStyle {
    /// The one style of the spike (docs/decisions.md, 80): heavy capitals in white with a thick black outline
    /// and a soft shadow, a few words at a time, the page popping in, the word being said turning yellow and
    /// springing up, an emphasised word in green and bigger. In the layout's free room.
    ///
    /// Every number is a starting value, to judge by eye (AUTHOR'S TAKE NEEDED). AvenirNext-Heavy ships with macOS.
    public static func pop(for output: OutputShape) -> CaptionStyle {
        let short = output == .vertical
        return CaptionStyle(
            name: "Pop",
            words: Words(atOnce: short ? 3 : 4, characters: short ? 20 : 30, lines: 2, width: short ? 0.84 : 0.62,
                         uppercase: true, keepsPunctuation: false),
            lettering: Lettering(font: "AvenirNext-Heavy", size: short ? 0.083 : 0.068, lineSpacing: 1.08, wordSpacing: 0.24, fill: "#FFFFFF",
                       stroke: Stroke(width: 0.13, color: "#000000"), shadow: Shadow(color: "#000000", opacity: 0.5, blur: 0.14, drop: 0.06)),
            spoken: Spoken(reach: .word, fill: "#FFD60A", box: nil, scale: 1.1),
            entrance: Entrance(reveal: .page, motion: .pop, duration: 0.12, exit: 0.06),
            spring: Spring(period: 0.3, damping: 0.6),
            emphasis: Emphasis(fill: "#32D74B", scale: 1.15),
            position: .free,
            offset: 0
        )
    }

    /// The styles that can be chosen. Adding a style is adding a value here.
    public static func catalog(for output: OutputShape) -> [CaptionStyle] {
        [pop(for: output)]
    }

    /// A catalog style by name, ignoring case.
    public static func named(_ name: String, for output: OutputShape) -> CaptionStyle? {
        catalog(for: output).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

extension CaptionStyle {
    /// The style with some of its values changed, given as the same JSON shape it's stored in, such as
    /// `{"spoken": {"fill": "#00FF66"}, "words": {"atOnce": 2}}`: objects merge key by key, anything else
    /// replaces, and `null` takes an optional part away. Lets a value be tried without a new style in code.
    public func changing(with changes: Data) throws -> CaptionStyle {
        let current = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        let asked = try JSONSerialization.jsonObject(with: changes, options: [.fragmentsAllowed])
        guard let currentObject = current as? [String: Any], let askedObject = asked as? [String: Any] else {
            throw CaptionStyleError.notAnObject
        }
        let merged = Self.merge(currentObject, askedObject)
        let style = try JSONDecoder().decode(CaptionStyle.self, from: JSONSerialization.data(withJSONObject: merged))
        if let problem = style.problem { throw CaptionStyleError.invalid(problem) }
        return style
    }

    private static func merge(_ base: [String: Any], _ changes: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in changes {
            if value is NSNull {
                result[key] = nil
            } else if let inner = value as? [String: Any], let existing = base[key] as? [String: Any] {
                result[key] = merge(existing, inner)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

/// Why a caption style's changes couldn't be made.
public enum CaptionStyleError: Error, Equatable, LocalizedError {
    case notAnObject
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .notAnObject: "Style changes are an object, like {\"spoken\": {\"fill\": \"#00FF66\"}}."
        case .invalid(let problem): problem
        }
    }
}

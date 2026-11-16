import Foundation

/// What happened on screen while a take recorded (docs/decisions.md, 58; docs/design.md, "The screen
/// log"): app and window changes, the cursor, clicks, drags and scrolling, when keys were pressed, and the
/// pointer's path. Which keys, and so what was typed, is never logged.
///
/// Each take's log is two JSON Lines files in the project's `screen/` folder, named after the take's folder
/// in `recordings/`: `<take>.events.jsonl` and `<take>.pointer.jsonl`, the pointer's path, which is long and
/// read only when asked. Times are in the source's time, like transcripts, so every cut maps onto them.
/// Positions are fractions of the capture area, from its top left; a pointer outside the area is below 0 or
/// above 1. The source names its log with ``Source/screenLog``.
public enum ScreenLog {
    public static let eventsSuffix = ".events.jsonl"
    public static let pointerSuffix = ".pointer.jsonl"

    /// The events file for a log, in a project.
    public static func eventsURL(_ name: String, in project: URL) -> URL {
        project.appending(path: "screen/\(name)\(eventsSuffix)")
    }

    /// The pointer's path for a log, in a project.
    public static func pointerURL(_ name: String, in project: URL) -> URL {
        project.appending(path: "screen/\(name)\(pointerSuffix)")
    }

    /// A position, as fractions of the capture area from its top left.
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        /// Whether it's inside the capture area.
        public var isInArea: Bool { (0...1).contains(x) && (0...1).contains(y) }
    }

    public enum EventType: String, Codable, Sendable {
        /// The first line: the capture area's size in points, and the display's scale, so positions can be
        /// turned into the screen track's pixels.
        case area
        /// Another app came to the front, with its frontmost window.
        case app
        /// The front app's focused window changed, or its title did.
        case window
        /// The pointer's cursor changed, such as from the arrow to the I-beam.
        case cursor
        /// A mouse button went down: `count` is 2 for a double-click.
        case click
        /// A button was held and the pointer moved before it came up: from `at` to `to`, ending at `end`.
        case drag
        /// Scrolling, from `t` to `end`, gathered while it kept coming: `dx` and `dy` in points.
        case scroll
        /// Typing, from `t` to `end`, gathered while it kept coming: `count` key presses in the front app. Never
        /// which keys.
        case keys
        /// A key pressed while ⌘, ⌃ or ⌥ was held: `modifiers` says which, never the key itself.
        case shortcut
    }

    /// A modifier key held for a shortcut.
    public enum Modifier: String, Codable, Sendable, CaseIterable {
        case command, control, option, shift
    }

    public enum Button: String, Codable, Sendable {
        case left, right, other
    }

    /// One line of the events file. Which fields are set depends on ``type``.
    public struct Event: Codable, Equatable, Sendable {
        /// When, in seconds of source time.
        public var t: TimeInterval
        public var type: EventType
        /// The end, for a drag or a scroll.
        public var end: TimeInterval?
        /// The app's name, and its bundle identifier.
        public var app: String?
        public var bundleID: String?
        /// The window's title, when macOS gives it.
        public var window: String?
        /// Where, for clicks, drags and scrolls.
        public var at: Point?
        /// Where a drag ended.
        public var to: Point?
        public var button: Button?
        /// Clicks in a row (1, or 2 for a double-click), or key presses in a ``EventType/keys`` line, or in a
        /// ``EventType/shortcut`` line, more than one when the same modifiers stayed held.
        public var count: Int?
        /// The modifiers held for a shortcut.
        public var modifiers: [Modifier]?
        public var dx: Double?
        public var dy: Double?
        /// The cursor's name when it's one of the system's standard cursors ("arrow", "iBeam",
        /// "pointingHand"…), otherwise "other".
        public var cursor: String?
        /// A fingerprint of the cursor's picture, the same for the same cursor, so cursors without a name can
        /// still be told apart.
        public var cursorID: String?
        /// For ``EventType/area``: the area's size in points and the display's pixels per point.
        public var width: Double?
        public var height: Double?
        public var scale: Double?

        public init(t: TimeInterval, type: EventType) {
            self.t = t
            self.type = type
        }

        /// The same event, moved in time.
        public func shifted(by offset: TimeInterval) -> Event {
            var event = self
            event.t += offset
            event.end = end.map { $0 + offset }
            return event
        }
    }

    /// One line of the pointer file: where the pointer was.
    public struct PointerSample: Codable, Equatable, Sendable {
        public var t: TimeInterval
        public var x: Double
        public var y: Double

        public init(t: TimeInterval, x: Double, y: Double) {
            self.t = t
            self.x = x
            self.y = y
        }
    }

    // MARK: - Reading and writing

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// One line of JSON, ending in a newline.
    public static func line(_ value: some Encodable) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    /// The lines of a JSON Lines file that read as `T`. A line that doesn't, such as the last one of a log
    /// cut short by a crash, is skipped.
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(T.self, from: Data($0)) }
    }

    /// Rewrites a log written on the recording's clock into source time: every time moves by `offset`.
    /// Clicks, drags and scrolls before source time zero are dropped; the area, and the last app, window and
    /// cursor before it, are what's on screen at zero, so they're kept there. Written atomically, so the log
    /// is never left half-written.
    public static func shift(eventsAt events: URL, pointerAt pointer: URL, by offset: TimeInterval) throws {
        try write(shifted(try read(Event.self, from: events), by: offset), to: events)
        if FileManager.default.fileExists(atPath: pointer.path(percentEncoded: false)) {
            let shiftedPointer = try read(PointerSample.self, from: pointer)
                .map { PointerSample(t: $0.t + offset, x: $0.x, y: $0.y) }
                .filter { $0.t >= 0 }
            try write(shiftedPointer, to: pointer)
        }
    }

    /// Events moved into source time, as ``shift(eventsAt:pointerAt:by:)`` writes them.
    public static func shifted(_ events: [Event], by offset: TimeInterval) -> [Event] {
        let moved = events.map { $0.shifted(by: offset) }
        let states: Set<EventType> = [.area, .app, .window, .cursor]
        // The last of each state before zero, moved to zero.
        var before: [EventType: Event] = [:]
        for event in moved where event.t < 0 && states.contains(event.type) { before[event.type] = event }
        let atZero = [EventType.area, .app, .window, .cursor].compactMap { type in
            before[type].map { event -> Event in
                var event = event
                event.t = 0
                return event
            }
        }
        return atZero + moved.filter { $0.t >= 0 }
    }

    private static func write(_ values: [some Encodable], to url: URL) throws {
        var data = Data()
        for value in values { data.append(try line(value)) }
        try data.write(to: url, options: .atomic)
    }
}

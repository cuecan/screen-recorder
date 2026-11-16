import CoreGraphics
import Foundation
import ProjectKit

/// The rules of the screen log (docs/decisions.md, 58), apart from AppKit, so they can be tested: turning
/// what the logger sees into ``ScreenLog`` lines. Times are on the recording's clock; nil means paused.
///
/// - A press becomes a click at once; if the pointer then moves more than ``dragDistance`` before the
///   button comes up, a drag too.
/// - Scrolling is gathered into one line while it keeps coming, and written once it stops for
///   ``scrollGap`` or the app under it changes.
/// - Key presses are gathered into one ``ScreenLog/EventType/keys`` line while they keep coming, written once
///   they stop for ``typingGap`` or the front app changes. A press with ⌘, ⌃ or ⌥ held is a
///   ``ScreenLog/EventType/shortcut`` line instead. Which key is never known: only how many were pressed.
/// - App, window and cursor lines are written only when they change; the pointer only when it moves.
public struct ScreenActivityTracker: Sendable {
    /// How far the pointer moves, in points, before a held button is a drag.
    public static let dragDistance: CGFloat = 4
    /// How long scrolling can pause and still be one scroll.
    public static let scrollGap: TimeInterval = 0.35
    /// The smallest move of the pointer worth a line, as a fraction of the area.
    public static let pointerStep = 0.0005
    /// How long typing can pause and still be one stretch of typing.
    public static let typingGap: TimeInterval = 1.0

    /// What's under the pointer: the app and its window.
    public struct Target: Equatable, Sendable {
        public var app: String?
        public var bundleID: String?
        public var window: String?

        public init(app: String? = nil, bundleID: String? = nil, window: String? = nil) {
            self.app = app
            self.bundleID = bundleID
            self.window = window
        }
    }

    /// A cursor, by fingerprint, with its name when it's a standard one.
    public struct Cursor: Equatable, Sendable {
        public var name: String
        public var id: String

        public init(name: String, id: String) {
            self.name = name
            self.id = id
        }
    }

    private struct Press {
        let time: TimeInterval
        let start: CGPoint
        let at: ScreenLog.Point
        let button: ScreenLog.Button
        let target: Target
        var moved = false
    }

    private struct Scroll {
        let start: TimeInterval
        var last: TimeInterval
        var dx: Double
        var dy: Double
        let at: ScreenLog.Point
        let target: Target
    }

    private struct Typing {
        let start: TimeInterval
        var last: TimeInterval
        var count: Int
        let target: Target
    }

    private var front: Target?
    private var typing: Typing?

    /// The front app and window, as last seen: where typing goes.
    public var frontTarget: Target { front ?? Target() }
    private var cursor: Cursor?
    private var press: Press?
    private var scroll: Scroll?
    private var pointer: ScreenLog.Point?

    public init() {}

    // MARK: - State

    /// The front app and its focused window, looked at often. A line when either changes.
    public mutating func front(_ target: Target, at time: TimeInterval?) -> ScreenLog.Event? {
        guard let time, target != front else { return nil }
        let isNewApp = target.bundleID != front?.bundleID || target.app != front?.app
        front = target
        var event = ScreenLog.Event(t: time, type: isNewApp ? .app : .window)
        event.app = target.app
        event.bundleID = target.bundleID
        event.window = target.window
        return event
    }

    /// The cursor the system shows now. A line when it changes.
    public mutating func cursor(_ cursor: Cursor, at time: TimeInterval?) -> ScreenLog.Event? {
        guard let time, cursor != self.cursor else { return nil }
        self.cursor = cursor
        var event = ScreenLog.Event(t: time, type: .cursor)
        event.cursor = cursor.name
        event.cursorID = cursor.id
        return event
    }

    /// The pointer, sampled many times a second. A sample when it has moved.
    public mutating func pointer(_ point: ScreenLog.Point, at time: TimeInterval?) -> ScreenLog.PointerSample? {
        guard let time else { return nil }
        if let last = pointer, abs(last.x - point.x) < Self.pointerStep, abs(last.y - point.y) < Self.pointerStep { return nil }
        pointer = point
        return ScreenLog.PointerSample(t: time, x: Self.rounded(point.x), y: Self.rounded(point.y))
    }

    // MARK: - Clicks and drags

    /// A button went down, at `location` in global points and `point` in the area.
    public mutating func pressed(_ button: ScreenLog.Button, count: Int, location: CGPoint, point: ScreenLog.Point,
                                 target: Target, at time: TimeInterval?) -> ScreenLog.Event? {
        guard let time else {
            press = nil
            return nil
        }
        press = Press(time: time, start: location, at: point, button: button, target: target)
        var event = ScreenLog.Event(t: time, type: .click)
        event.button = button
        event.count = max(1, count)
        event.at = Self.rounded(point)
        Self.fill(&event, with: target)
        return event
    }

    /// The pointer moved with a button held.
    public mutating func dragged(to location: CGPoint) {
        guard var press, !press.moved else { return }
        if hypot(location.x - press.start.x, location.y - press.start.y) > Self.dragDistance {
            press.moved = true
            self.press = press
        }
    }

    /// The button came up. A drag line if the pointer moved far enough while it was held.
    public mutating func released(_ button: ScreenLog.Button, location: CGPoint, point: ScreenLog.Point, at time: TimeInterval?) -> ScreenLog.Event? {
        defer { press = nil }
        dragged(to: location)
        guard let time, let press, press.button == button, press.moved else { return nil }
        var event = ScreenLog.Event(t: press.time, type: .drag)
        event.end = time
        event.button = button
        event.at = Self.rounded(press.at)
        event.to = Self.rounded(point)
        Self.fill(&event, with: press.target)
        return event
    }

    // MARK: - Scrolling

    /// A scroll came in. A line for the scroll before, if this one starts another.
    public mutating func scrolled(dx: Double, dy: Double, point: ScreenLog.Point, target: Target, at time: TimeInterval?) -> ScreenLog.Event? {
        guard let time else { return flushScroll() }
        var finished: ScreenLog.Event?
        if let current = scroll, time - current.last > Self.scrollGap || current.target != target {
            finished = flushScroll()
        }
        if var current = scroll {
            current.last = time
            current.dx += dx
            current.dy += dy
            scroll = current
        } else {
            scroll = Scroll(start: time, last: time, dx: dx, dy: dy, at: point, target: target)
        }
        return finished
    }

    /// The scroll under way, if scrolling has stopped by `time`.
    public mutating func scrollEnded(by time: TimeInterval?) -> ScreenLog.Event? {
        guard let current = scroll else { return nil }
        if let time, time - current.last <= Self.scrollGap { return nil }
        return flushScroll()
    }

    /// Ends the scroll under way, such as on Stop.
    public mutating func flushScroll() -> ScreenLog.Event? {
        guard let current = scroll else { return nil }
        scroll = nil
        var event = ScreenLog.Event(t: current.start, type: .scroll)
        event.end = current.last
        event.dx = (current.dx * 10).rounded() / 10
        event.dy = (current.dy * 10).rounded() / 10
        event.at = Self.rounded(current.at)
        Self.fill(&event, with: current.target)
        return event
    }

    // MARK: - Keys

    /// Keys pressed since the last look: `count` presses, with `modifiers` held now. Returns the lines to
    /// write: a shortcut at once, and a stretch of typing once it has ended.
    public mutating func keysPressed(_ count: Int, modifiers: [ScreenLog.Modifier], target: Target, at time: TimeInterval?) -> [ScreenLog.Event] {
        guard let time else { return [flushTyping()].compactMap { $0 } }
        var lines: [ScreenLog.Event] = []
        if let current = typing, time - current.last > Self.typingGap || (count > 0 && current.target != target) {
            lines += [flushTyping()].compactMap { $0 }
        }
        guard count > 0 else { return lines }
        if modifiers.contains(where: { $0 != .shift }) {
            var shortcut = ScreenLog.Event(t: time, type: .shortcut)
            shortcut.modifiers = ScreenLog.Modifier.allCases.filter(modifiers.contains)
            shortcut.count = count
            Self.fill(&shortcut, with: target)
            return lines + [shortcut]
        }
        if var current = typing {
            current.last = time
            current.count += count
            typing = current
        } else {
            typing = Typing(start: time, last: time, count: count, target: target)
        }
        return lines
    }

    /// Ends the stretch of typing under way, such as on Stop.
    public mutating func flushTyping() -> ScreenLog.Event? {
        guard let current = typing else { return nil }
        typing = nil
        var event = ScreenLog.Event(t: current.start, type: .keys)
        event.end = current.last
        event.count = current.count
        Self.fill(&event, with: current.target)
        return event
    }

    // MARK: - Positions

    /// A point in AppKit's global coordinates as fractions of the area, from its top left.
    public static func point(_ location: CGPoint, in area: CGRect) -> ScreenLog.Point {
        ScreenLog.Point(x: (location.x - area.minX) / max(area.width, 1), y: (area.maxY - location.y) / max(area.height, 1))
    }

    private static func rounded(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }

    private static func rounded(_ point: ScreenLog.Point) -> ScreenLog.Point {
        ScreenLog.Point(x: rounded(point.x), y: rounded(point.y))
    }

    private static func fill(_ event: inout ScreenLog.Event, with target: Target) {
        event.app = target.app
        event.bundleID = target.bundleID
        event.window = target.window
    }
}

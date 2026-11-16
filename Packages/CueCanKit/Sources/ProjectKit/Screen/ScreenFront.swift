import Foundation

/// What was in front on screen from a moment on: an app and its window, from the screen log's `app` and
/// `window` lines (docs/decisions.md, 58), for the transcript's rail (docs/ui.md, "The transcript in the
/// inspector").
public struct ScreenFront: Equatable, Sendable {
    /// When it came to the front, in source time.
    public var start: TimeInterval
    public var app: String
    public var bundleID: String?
    /// The window's title, when macOS gave it.
    public var window: String?

    public init(start: TimeInterval, app: String, bundleID: String? = nil, window: String? = nil) {
        self.start = start
        self.app = app
        self.bundleID = bundleID
        self.window = window
    }

    /// Whether it's the same app as another, by bundle identifier when both have one.
    public func isSameApp(as other: ScreenFront) -> Bool {
        if let bundleID, let otherID = other.bundleID { return bundleID == otherID }
        return app == other.app
    }

    /// Whether it's the same app and window as another.
    public func isSameWindow(as other: ScreenFront) -> Bool {
        isSameApp(as: other) && window == other.window
    }

    /// How long an app or window has to stay in front to count (as asked: "some kind of debounce"). Claude's call,
    /// to tune on real takes.
    public static let settlingTime: TimeInterval = 2

    /// What was in front, settled: an app or window counts only once it stays for ``settlingTime``, so a
    /// quick switch away and back leaves no trace, and the stretch carries on as one.
    ///
    /// - Parameters:
    ///   - events: A source's screen log, in source time.
    ///   - end: When the recording ends, so the last thing in front can settle.
    public static func settled(from events: [ScreenLog.Event], until end: TimeInterval, settlingTime: TimeInterval = settlingTime) -> [ScreenFront] {
        // Every change, in order, each with the app it belongs to.
        var changes: [ScreenFront] = []
        for event in events.sorted(by: { $0.t < $1.t }) {
            switch event.type {
            case .app:
                guard let app = event.app else { continue }
                changes.append(ScreenFront(start: event.t, app: app, bundleID: event.bundleID, window: event.window))
            case .window:
                guard var front = changes.last else { continue }
                if let app = event.app, app != front.app {
                    front.app = app
                    front.bundleID = event.bundleID
                }
                front.start = event.t
                front.window = event.window
                changes.append(front)
            default:
                continue
            }
        }
        var settled: [ScreenFront] = []
        for (index, change) in changes.enumerated() {
            let until = index + 1 < changes.count ? changes[index + 1].start : end
            guard until - change.start >= settlingTime || (settled.isEmpty && index + 1 == changes.count) else { continue }
            if let last = settled.last, last.isSameWindow(as: change) { continue }
            // The first thing in front counts from the start, however it began.
            var change = change
            if settled.isEmpty { change.start = min(change.start, changes.first?.start ?? change.start) }
            settled.append(change)
        }
        return settled
    }

    /// What was in front at a time, from settled fronts in order.
    public static func front(at time: TimeInterval, in fronts: [ScreenFront]) -> ScreenFront? {
        fronts.last { $0.start <= time } ?? fronts.first
    }
}

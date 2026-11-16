import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import ProjectKit

/// Logs what happens on screen while a take records (docs/decisions.md, 58): the front app and window, the
/// pointer and its cursor, clicks, drags, scrolling, and when keys were pressed, into the project's
/// `screen/` folder (``ScreenLog``). What was typed is never logged: key presses are counted, not watched.
///
/// It needs no permission the app doesn't already have: watching other apps' mouse events doesn't need
/// Input Monitoring; key presses come from the window server's count of them (`CGEventSource`), which
/// tells how many, never which, and needs no permission; window titles come from Accessibility, which
/// window snapping already uses, or from the window list, which Screen Recording access opens up. Without
/// them, titles are left out. While macOS has secure input on, such as in a password field, key presses
/// aren't counted at all.
///
/// Lines are written as they happen, on the recording's clock, so a crash keeps what was logged. On Stop,
/// ``finish(clockOffset:)`` moves them into source time.
@MainActor
public final class ScreenActivityLogger {
    /// The log's name in `screen/`: the take's folder name.
    public let name: String
    private let projectURL: URL
    /// The capture area, in AppKit's global coordinates.
    private let area: CGRect
    private let scale: Double
    private let clock: RecordingClock
    private var tracker = ScreenActivityTracker()
    private var events: FileHandle?
    private var pointer: FileHandle?
    private var monitors: [Any] = []
    private var timers: [Timer] = []
    private let ownProcess = ProcessInfo.processInfo.processIdentifier
    /// The standard cursors' fingerprints, for naming the cursor shown.
    private lazy var standardCursors = CursorFingerprint.standardCursors()
    /// The window server's count of key presses when last looked at.
    private var keyCount: UInt32 = 0
    /// The app under a scroll, looked up at most every so often, since scrolls come many times a second.
    private var scrollTarget: (time: TimeInterval, target: ScreenActivityTracker.Target)?

    /// A logger for a take, writing to `screen/<name>.events.jsonl` and `screen/<name>.pointer.jsonl`.
    public init(project: URL, name: String, area: CGRect, scale: Double, clock: RecordingClock) {
        self.projectURL = project
        self.name = name
        self.area = area
        self.scale = scale
        self.clock = clock
    }

    private var eventsURL: URL { ScreenLog.eventsURL(name, in: projectURL) }
    private var pointerURL: URL { ScreenLog.pointerURL(name, in: projectURL) }

    /// Starts logging, with what's on screen now. Call it after the session's clock has started.
    public func start() throws {
        let folder = eventsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in [eventsURL, pointerURL] {
            guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
                throw RecorderError.couldNotWrite(url, "The screen log couldn't be created.")
            }
        }
        events = try FileHandle(forWritingTo: eventsURL)
        pointer = try FileHandle(forWritingTo: pointerURL)

        var areaLine = ScreenLog.Event(t: now ?? 0, type: .area)
        areaLine.width = area.width
        areaLine.height = area.height
        areaLine.scale = scale
        write(areaLine)
        lookAtFront()
        lookAtCursor()
        samplePointer()
        keyCount = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(monitor)
        }
        timers = [
            repeating(1.0 / 30) { $0.samplePointer() },
            repeating(1.0 / 10) { $0.lookAtCursor() },
            repeating(1.0 / 4) { $0.lookAtFront() },
            repeating(1.0 / 20) { $0.countKeys() },
        ]
    }

    /// Stops logging and closes the files, still on the recording's clock.
    public func stop() {
        if let scroll = tracker.flushScroll() { write(scroll) }
        if let typing = tracker.flushTyping() { write(typing) }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        for timer in timers { timer.invalidate() }
        timers.removeAll()
        try? events?.close()
        try? pointer?.close()
        events = nil
        pointer = nil
    }

    /// Stops, and moves the log into source time: `clockOffset` is where source time zero falls on the
    /// recording's clock (``RecordedSource/clockOffset``). Returns the log's name, for its source.
    public func finish(clockOffset: TimeInterval) throws -> String {
        stop()
        try ScreenLog.shift(eventsAt: eventsURL, pointerAt: pointerURL, by: -clockOffset)
        return name
    }

    /// Stops and deletes the log, for a discarded take.
    public func discard() {
        stop()
        try? FileManager.default.removeItem(at: eventsURL)
        try? FileManager.default.removeItem(at: pointerURL)
    }

    // MARK: - Watching

    /// The recording's clock now, or nil while paused.
    private var now: TimeInterval? { clock.place(RecordingClock.hostNow) }

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let point = ScreenActivityTracker.point(location, in: area)
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if let line = tracker.pressed(Self.button(event), count: event.clickCount, location: location, point: point,
                                          target: target(at: location), at: now) {
                write(line)
            }
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            tracker.dragged(to: location)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if let line = tracker.released(Self.button(event), location: location, point: point, at: now) { write(line) }
        case .scrollWheel:
            // Trackpads and Magic Mice report points; a wheel reports lines.
            let time = now
            let target: ScreenActivityTracker.Target
            if let cached = scrollTarget, let time, time - cached.time < 0.25 {
                target = cached.target
            } else {
                target = self.target(at: location)
                if let time { scrollTarget = (time, target) }
            }
            if let line = tracker.scrolled(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, point: point, target: target, at: time) {
                write(line)
            }
        default:
            break
        }
    }

    private func samplePointer() {
        let time = now
        if let sample = tracker.pointer(ScreenActivityTracker.point(NSEvent.mouseLocation, in: area), at: time) { write(sample) }
        if let scroll = tracker.scrollEnded(by: time) { write(scroll) }
    }

    /// How many keys were pressed since the last look, with the modifiers held now. Which keys is never
    /// known. Autorepeat isn't counted, and modifier keys alone aren't key presses.
    private func countKeys() {
        let count = CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
        let pressed = Int(count &- keyCount)
        keyCount = count
        // In a password field, or anywhere macOS has secure input on, not even the count is kept.
        let presses = IsSecureEventInputEnabled() ? 0 : pressed
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var modifiers: [ScreenLog.Modifier] = []
        if flags.contains(.maskCommand) { modifiers.append(.command) }
        if flags.contains(.maskControl) { modifiers.append(.control) }
        if flags.contains(.maskAlternate) { modifiers.append(.option) }
        if flags.contains(.maskShift) { modifiers.append(.shift) }
        for line in tracker.keysPressed(presses, modifiers: modifiers, target: tracker.frontTarget, at: now) { write(line) }
    }

    private func lookAtCursor() {
        guard let cursor = NSCursor.currentSystem else { return }
        let id = CursorFingerprint.of(cursor)
        let name = standardCursors[id] ?? "other"
        if let line = tracker.cursor(.init(name: name, id: id), at: now) { write(line) }
    }

    private func lookAtFront() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownProcess else { return }
        let target = ScreenActivityTracker.Target(
            app: app.localizedName,
            bundleID: app.bundleIdentifier,
            window: Self.focusedWindowTitle(of: app.processIdentifier) ?? Self.frontWindowTitle(of: app.processIdentifier)
        )
        if let line = tracker.front(target, at: now) { write(line) }
    }

    // MARK: - What's where

    /// The app and window under a point in AppKit's global coordinates: the topmost ordinary window there
    /// that isn't CueCan's.
    private func target(at location: CGPoint) -> ScreenActivityTracker.Target {
        // The window list is in global coordinates from the top left of the main display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: primaryHeight - location.y)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownProcess,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0).contains(point)
            else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .init(app: app?.localizedName ?? info[kCGWindowOwnerName as String] as? String, bundleID: app?.bundleIdentifier, window: title)
        }
        return .init()
    }

    /// The app's focused window's title, through Accessibility.
    private static func focusedWindowTitle(of pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        // A hung app mustn't hold up the recording's main thread.
        AXUIElementSetMessagingTimeout(app, 0.1)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(unsafeDowncast(window, to: AXUIElement.self), kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return (title as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The app's frontmost window's title, from the window list, when Accessibility doesn't give it.
    private static func frontWindowTitle(of pid: pid_t) -> String? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let window = list.first { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
        return (window?[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func button(_ event: NSEvent) -> ScreenLog.Button {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: .right
        default: .other
        }
    }

    // MARK: - Writing

    private func write(_ event: ScreenLog.Event) {
        guard let events, let data = try? ScreenLog.line(event) else { return }
        try? events.write(contentsOf: data)
    }

    private func write(_ sample: ScreenLog.PointerSample) {
        guard let pointer, let data = try? ScreenLog.line(sample) else { return }
        try? pointer.write(contentsOf: data)
    }

    private func repeating(_ interval: TimeInterval, _ action: @escaping @MainActor (ScreenActivityLogger) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

/// A short fingerprint of a cursor's picture and hot spot, the same each time the same cursor shows, so the
/// log can name the standard ones and tell the others apart. Whether macOS hands over other apps' cursors
/// faithfully at every cursor size is VERIFY (docs/decisions.md, 58).
enum CursorFingerprint {
    static let side = 16

    @MainActor
    static func of(_ cursor: NSCursor) -> String {
        let image = cursor.image
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return "unknown" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        // FNV-1a over the pixels, coarsened so antialiasing noise doesn't change it, and the hot spot as a
        // share of the picture.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        if let data = bitmap.bitmapData {
            for index in 0..<(side * side * 4) { mix(data[index] >> 4) }
        }
        let size = image.size
        mix(UInt8(min(255, max(0, cursor.hotSpot.x / max(size.width, 1) * 16))))
        mix(UInt8(min(255, max(0, cursor.hotSpot.y / max(size.height, 1) * 16))))
        return String(format: "%08llx", hash >> 32)
    }

    /// The system's standard cursors, by fingerprint.
    @MainActor
    static func standardCursors() -> [String: String] {
        let cursors: [(String, NSCursor)] = [
            ("arrow", .arrow), ("iBeam", .iBeam), ("pointingHand", .pointingHand), ("openHand", .openHand),
            ("closedHand", .closedHand), ("crosshair", .crosshair), ("resizeLeftRight", .resizeLeftRight),
            ("resizeUpDown", .resizeUpDown), ("operationNotAllowed", .operationNotAllowed), ("dragCopy", .dragCopy),
            ("contextualMenu", .contextualMenu), ("iBeamVertical", .iBeamCursorForVerticalLayout),
        ]
        var names: [String: String] = [:]
        for (name, cursor) in cursors where names[of(cursor)] == nil { names[of(cursor)] = name }
        return names
    }
}

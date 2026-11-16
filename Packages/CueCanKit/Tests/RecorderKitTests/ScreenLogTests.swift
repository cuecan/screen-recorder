import CoreGraphics
import Foundation
import Testing
import ProjectKit
@testable import RecorderKit

/// The screen log's rules and its files (docs/decisions.md, 58).
@Suite struct ScreenLogTests {
    let target = ScreenActivityTracker.Target(app: "Xcode", bundleID: "com.apple.dt.Xcode", window: "RecorderModel.swift")
    let point = ScreenLog.Point(x: 0.4, y: 0.6)

    @Test func aPressIsAClickAndADragOnlyIfThePointerMoved() throws {
        var tracker = ScreenActivityTracker()
        let clickLine = tracker.pressed(.left, count: 2, location: CGPoint(x: 100, y: 100), point: point, target: target, at: 1.5)
        let click = try #require(clickLine)
        #expect(click.type == .click)
        #expect(click.count == 2, "A double-click says so.")
        #expect(click.app == "Xcode")
        #expect(click.window == "RecorderModel.swift")
        // A wobble isn't a drag.
        tracker.dragged(to: CGPoint(x: 102, y: 101))
        #expect(tracker.released(.left, location: CGPoint(x: 102, y: 101), point: point, at: 1.6) == nil)

        _ = tracker.pressed(.left, count: 1, location: CGPoint(x: 100, y: 100), point: point, target: target, at: 2)
        tracker.dragged(to: CGPoint(x: 160, y: 90))
        let dragLine = tracker.released(.left, location: CGPoint(x: 160, y: 90), point: ScreenLog.Point(x: 0.5, y: 0.65), at: 2.8)
        let drag = try #require(dragLine)
        #expect(drag.type == .drag)
        #expect(drag.t == 2)
        #expect(drag.end == 2.8)
        #expect(drag.at == point)
        #expect(drag.to == ScreenLog.Point(x: 0.5, y: 0.65))
    }

    @Test func nothingIsLoggedWhilePaused() {
        var tracker = ScreenActivityTracker()
        #expect(tracker.pressed(.left, count: 1, location: .zero, point: point, target: target, at: nil) == nil)
        #expect(tracker.pointer(point, at: nil) == nil)
        #expect(tracker.front(target, at: nil) == nil)
        // The front app is logged once recording resumes, because it wasn't seen while paused.
        #expect(tracker.front(target, at: 4)?.type == .app)
    }

    @Test func scrollingIsGatheredUntilItStops() throws {
        var tracker = ScreenActivityTracker()
        #expect(tracker.scrolled(dx: 0, dy: -10, point: point, target: target, at: 1) == nil)
        #expect(tracker.scrolled(dx: 0, dy: -12.5, point: point, target: target, at: 1.1) == nil)
        #expect(tracker.scrollEnded(by: 1.2) == nil, "Still scrolling.")
        let scrollLine = tracker.scrollEnded(by: 1.6)
        let scroll = try #require(scrollLine)
        #expect(scroll.type == .scroll)
        #expect(scroll.t == 1)
        #expect(scroll.end == 1.1)
        #expect(scroll.dy == -22.5)
        #expect(scroll.app == "Xcode")
        // Scrolling in another app starts another scroll.
        _ = tracker.scrolled(dx: 0, dy: 5, point: point, target: target, at: 3)
        let other = ScreenActivityTracker.Target(app: "Safari", bundleID: "com.apple.Safari")
        let finishedLine = tracker.scrolled(dx: 0, dy: 5, point: point, target: other, at: 3.1)
        let finished = try #require(finishedLine)
        #expect(finished.app == "Xcode")
        #expect(tracker.flushScroll()?.app == "Safari")
    }

    @Test func typingIsCountedNeverRead() throws {
        var tracker = ScreenActivityTracker()
        #expect(tracker.keysPressed(3, modifiers: [], target: target, at: 1).isEmpty)
        #expect(tracker.keysPressed(4, modifiers: [.shift], target: target, at: 1.4).isEmpty, "Shift is typing, not a shortcut.")
        #expect(tracker.keysPressed(0, modifiers: [], target: target, at: 1.8).isEmpty, "Still typing.")
        let typingLine = tracker.keysPressed(0, modifiers: [], target: target, at: 2.6).first
        let typing = try #require(typingLine)
        #expect(typing.type == .keys)
        #expect(typing.t == 1)
        #expect(typing.end == 1.4)
        #expect(typing.count == 7)
        #expect(typing.app == "Xcode")
        // The line has no field that could hold a character.
        let text = String(decoding: try ScreenLog.line(typing), as: UTF8.self)
        #expect(text == #"{"app":"Xcode","bundleID":"com.apple.dt.Xcode","count":7,"end":1.4,"t":1,"type":"keys","window":"RecorderModel.swift"}"# + "\n")
    }

    @Test func aShortcutSaysWhichModifiersButNotTheKey() throws {
        var tracker = ScreenActivityTracker()
        _ = tracker.keysPressed(2, modifiers: [], target: target, at: 1)
        let shortcutLine = tracker.keysPressed(1, modifiers: [.shift, .command], target: target, at: 1.2).last
        let shortcut = try #require(shortcutLine)
        #expect(shortcut.type == .shortcut)
        #expect(shortcut.modifiers == [.command, .shift])
        #expect(shortcut.count == 1)
        #expect(tracker.flushTyping()?.count == 2, "The shortcut isn't counted as typing.")
        // Typing in another app starts another stretch; nothing is logged while paused.
        _ = tracker.keysPressed(1, modifiers: [], target: target, at: 3)
        let other = ScreenActivityTracker.Target(app: "Terminal", bundleID: "com.apple.Terminal")
        #expect(tracker.keysPressed(1, modifiers: [], target: other, at: 3.2).first?.app == "Xcode")
        #expect(tracker.keysPressed(5, modifiers: [], target: other, at: nil).first?.count == 1, "Pausing ends the stretch.")
        #expect(tracker.flushTyping() == nil)
    }

    @Test func appWindowAndCursorAreLoggedWhenTheyChange() {
        var tracker = ScreenActivityTracker()
        #expect(tracker.front(target, at: 0)?.type == .app)
        #expect(tracker.front(target, at: 0.25) == nil)
        var renamed = target
        renamed.window = "Edit.swift"
        #expect(tracker.front(renamed, at: 0.5)?.type == .window, "The same app, another window.")
        #expect(tracker.front(.init(app: "Safari", bundleID: "com.apple.Safari"), at: 1)?.type == .app)
        let iBeam = ScreenActivityTracker.Cursor(name: "iBeam", id: "1a2b3c4d")
        #expect(tracker.cursor(iBeam, at: 1)?.cursor == "iBeam")
        #expect(tracker.cursor(iBeam, at: 1.1) == nil)
    }

    @Test func thePointerIsLoggedWhenItMoves() {
        var tracker = ScreenActivityTracker()
        #expect(tracker.pointer(point, at: 0) != nil)
        #expect(tracker.pointer(ScreenLog.Point(x: 0.40001, y: 0.6), at: 0.033) == nil)
        #expect(tracker.pointer(ScreenLog.Point(x: 0.41, y: 0.6), at: 0.066)?.x == 0.41)
    }

    @Test func positionsAreFractionsOfTheAreaFromItsTopLeft() {
        // AppKit's global coordinates go up from the bottom.
        let area = CGRect(x: 100, y: 200, width: 1000, height: 500)
        #expect(ScreenActivityTracker.point(CGPoint(x: 100, y: 700), in: area) == ScreenLog.Point(x: 0, y: 0))
        #expect(ScreenActivityTracker.point(CGPoint(x: 600, y: 450), in: area) == ScreenLog.Point(x: 0.5, y: 0.5))
        #expect(!ScreenActivityTracker.point(CGPoint(x: 50, y: 450), in: area).isInArea, "Outside the area is below 0.")
    }

    @Test func aLogMovesIntoSourceTimeKeepingWhatWasOnScreenAtZero() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "screenlog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let events = ScreenLog.eventsURL("take", in: folder)
        let pointer = ScreenLog.pointerURL("take", in: folder)
        try FileManager.default.createDirectory(at: events.deletingLastPathComponent(), withIntermediateDirectories: true)

        var area = ScreenLog.Event(t: 0, type: .area)
        area.width = 1280
        var app = ScreenLog.Event(t: 0.01, type: .app)
        app.app = "Xcode"
        let earlyClick = ScreenLog.Event(t: 0.05, type: .click)
        var lateClick = ScreenLog.Event(t: 2.3, type: .click)
        lateClick.app = "Xcode"
        var scroll = ScreenLog.Event(t: 3, type: .scroll)
        scroll.end = 3.5
        var lines = Data()
        for event in [area, app, earlyClick, lateClick, scroll] { lines.append(try ScreenLog.line(event)) }
        lines.append(Data("{\"t\": 4, \"type\": \"cli".utf8)) // cut short by a crash
        try lines.write(to: events)
        var points = Data()
        for sample in [ScreenLog.PointerSample(t: 0.05, x: 0.1, y: 0.1), ScreenLog.PointerSample(t: 1, x: 0.2, y: 0.2)] {
            points.append(try ScreenLog.line(sample))
        }
        try points.write(to: pointer)

        // Source time zero was 0.3 s into the recording's clock.
        try ScreenLog.shift(eventsAt: events, pointerAt: pointer, by: -0.3)
        let shifted = try ScreenLog.read(ScreenLog.Event.self, from: events)
        #expect(shifted.map(\.type) == [.area, .app, .click, .scroll])
        #expect(shifted[0].t == 0 && shifted[0].width == 1280)
        #expect(shifted[1].t == 0 && shifted[1].app == "Xcode", "The app in front at zero is kept at zero.")
        #expect(abs(shifted[2].t - 2.0) < 0.0001, "A click before zero is dropped; a later one moves.")
        #expect(abs((shifted[3].end ?? 0) - 3.2) < 0.0001)
        let samples = try ScreenLog.read(ScreenLog.PointerSample.self, from: pointer)
        #expect(samples.count == 1)
        #expect(abs(samples[0].t - 0.7) < 0.0001)
    }

    @Test func aLineIsCompactSortedJSON() throws {
        var click = ScreenLog.Event(t: 1.25, type: .click)
        click.button = .left
        click.count = 1
        let text = String(decoding: try ScreenLog.line(click), as: UTF8.self)
        #expect(text == #"{"button":"left","count":1,"t":1.25,"type":"click"}"# + "\n")
    }
}

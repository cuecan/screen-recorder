import AppKit
import ApplicationServices
import Foundation
import os

/// Moves and resizes other apps' windows to fill the capture area (docs/decisions.md, 21).
///
/// A window is snapped in by being dragged onto the area. An app that has been in snaps back in whenever
/// the creator switches to it; others are left alone. Snapped windows stay where they are when the
/// recording ends: nothing is put back.
/// It uses the Accessibility API, which asks for access the first time it's needed.
///
/// Snapping is TEST NEEDED in the apps recorded most: a browser, an editor, an Electron app, with minimum
/// sizes and full-screen windows (docs/design.md, "Open questions and checks").
@MainActor
public final class WindowSnapper {
    /// How far inside the area's edges a snapped window sits, in pixels of the area's display, so the
    /// window's own border and rounded corners are recorded whole rather than cut by the area's edge.
    /// A starting value, to judge by eye.
    public static let insetPixels = 2.0

    /// The frame a window snaps to inside an area: the area inset by ``insetPixels``, in points.
    public static func snapFrame(in area: CGRect) -> CGRect {
        let scale = NSScreen.screens.first { $0.frame.intersects(area) }?.backingScaleFactor ?? 2
        let inset = insetPixels / scale
        return area.insetBy(dx: inset, dy: inset)
    }

    /// The windows snapped in, so they can follow the area when it moves or changes size.
    private struct Remembered {
        let handle: WindowAccessWorker.Handle
        let processID: pid_t
        let frame: CGRect
        let area: CGRect
        let avoiding: [CGRect]
        let result: WindowSnapResult
    }
    private var snapped: [Remembered] = []
    private let access = WindowAccessWorker()
    private var latest = UUID()
    private var pending: (id: UUID, task: Task<WindowSnapOperation.Placement?, any Error>)?
    /// The apps that have been in the area, by process id.
    public private(set) var snappedApps: Set<pid_t> = []

    /// Why the last snap that returned nothing did.
    public enum Failure: Sendable, Equatable {
        /// The window is in full screen, which can't be moved or resized.
        case fullScreen
        /// The window couldn't be found among its app's windows, or the app didn't answer in time.
        case notFound
        /// It was asked to move and didn't end up where it was sent.
        case didNotMove
    }
    public private(set) var lastFailure: Failure?
    /// Each snap's steps go to the `com.jelled.CueCan` subsystem, category `snapping`, with what the other
    /// app answered, so a window that didn't fill the area can be explained from Console or Xcode's console.
    nonisolated static let log = Logger(subsystem: "com.jelled.CueCan", category: "snapping")

    public init() {}

    public static var hasAccess: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility access, showing the system prompt if it hasn't been given.
    @discardableResult
    public static func requestAccess() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: - Finding windows

    /// The normal windows other apps have on screen, front to back.
    public static func windows() -> [SnappableWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(window(from:))
    }

    /// The frontmost window of another app under a point, in AppKit's global coordinates.
    public static func window(at point: CGPoint) -> SnappableWindow? {
        windows().first { $0.frame.contains(point) }
    }

    /// Where a window is now, in AppKit's global coordinates. Nil once it's closed.
    public static func frame(ofWindow id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
            let info = list.first, let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        return appKitFrame(fromWindowServer: bounds)
    }

    private static func window(from info: [String: Any]) -> SnappableWindow? {
        guard (info[kCGWindowLayer as String] as? Int) == 0,
            let id = info[kCGWindowNumber as String] as? CGWindowID,
            let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ProcessInfo.processInfo.processIdentifier,
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
            let frame = appKitFrame(fromWindowServer: bounds), frame.width > 40, frame.height > 40
        else { return nil }
        return SnappableWindow(
            id: id,
            processID: pid,
            appName: info[kCGWindowOwnerName as String] as? String ?? "",
            title: info[kCGWindowName as String] as? String ?? "",
            frame: frame
        )
    }

    /// The window server's top-left bounds as an AppKit frame, from the bottom left of the main display.
    private static func appKitFrame(fromWindowServer bounds: [String: CGFloat]) -> CGRect? {
        guard let width = bounds["Width"], let height = bounds["Height"] else { return nil }
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: bounds["X"] ?? 0, y: mainHeight - (bounds["Y"] ?? 0) - height, width: width, height: height)
    }

    // MARK: - Snapping

    /// Tries the area's size, waits for the app to settle, then places a constrained window usefully.
    /// Smaller windows favor the center away from `avoiding`; larger windows start at the upper left.
    /// Nil means the window could not be identified or moved, rather than a proven size limit.
    @discardableResult
    public func snap(_ window: SnappableWindow, to area: CGRect, avoiding: [CGRect] = []) async -> WindowSnapResult? {
        let request = begin()
        let current = Self.frame(ofWindow: window.id) ?? window.frame
        guard let handle = await access.resolve(window, reference: Self.accessibilityFrame(from: current)) else {
            if isCurrent(request) {
                lastFailure = .notFound
                Self.log.notice("Snapping \(window.appName, privacy: .public): its window wasn't found, or the app didn't answer in time")
            }
            return nil
        }
        guard isCurrent(request) else { return nil }
        return await place(handle, processID: window.processID, in: area, avoiding: avoiding, request: request)
    }

    /// A window that was dragged in and is still in the area is put back in place when its app comes
    /// forward, in case the app changed its size meanwhile. Nothing else is touched: not
    /// another window of that app, and not a window the creator has since dragged out of the area or onto
    /// another display, which is forgotten.
    @discardableResult
    public func snapFocusedWindow(of processID: pid_t, to area: CGRect, avoiding: [CGRect] = []) async -> WindowSnapResult? {
        guard snappedApps.contains(processID) else { return nil }
        let request = begin()
        guard let handle = await access.focused(in: processID), isCurrent(request) else { return nil }
        guard let remembered = snapped.first(where: { CFEqual($0.handle.element, handle.element) }) else { return nil }
        guard let axFrame = await access.frame(handle), isCurrent(request) else { return nil }
        let frame = Self.accessibilityFrame(from: axFrame)
        guard WindowFit.isMostlyInside(frame, area: remembered.area) || WindowFit.isMostlyInside(frame, area: area) else {
            snapped.removeAll { CFEqual($0.handle.element, handle.element) }
            if !snapped.contains(where: { $0.processID == processID }) { snappedApps.remove(processID) }
            return nil
        }
        if remembered.area == area, remembered.avoiding == avoiding, WindowFit.fills(frame, area: remembered.frame) {
            return remembered.result
        }
        return await place(handle, processID: processID, in: area, avoiding: avoiding, request: request)
    }

    /// Follows an area or camera-side change, including windows placed smaller than the area. A window
    /// moved manually since the last snap is left alone.
    public func follow(from old: CGRect, to area: CGRect, avoiding: [CGRect] = []) async {
        let request = begin()
        for remembered in snapped where remembered.area == old {
            guard isCurrent(request) else { return }
            guard let frame = await access.frame(remembered.handle),
                  WindowFit.fills(Self.accessibilityFrame(from: frame), area: remembered.frame) else { continue }
            guard isCurrent(request) else { return }
            _ = await place(remembered.handle, processID: remembered.processID, in: area, avoiding: avoiding, request: request)
        }
    }

    /// Invalidates pending resizes without moving any window back.
    public func cancelPending() {
        latest = UUID()
        pending?.task.cancel()
        pending = nil
    }

    /// Forgets placed windows, leaving every one where the creator put it.
    public func forgetAll() {
        cancelPending()
        snapped.removeAll()
        snappedApps.removeAll()
    }

    public var hasSnappedWindows: Bool { !snapped.isEmpty }

    private func begin() -> UUID {
        cancelPending()
        lastFailure = nil
        return latest
    }

    private func isCurrent(_ request: UUID) -> Bool { latest == request && !Task.isCancelled }

    private func place(_ handle: WindowAccessWorker.Handle, processID: pid_t, in area: CGRect,
                       avoiding: [CGRect], request: UUID) async -> WindowSnapResult? {
        guard isCurrent(request) else { return nil }
        let name = NSRunningApplication(processIdentifier: processID)?.localizedName ?? "pid \(processID)"
        if await access.isFullScreen(handle) {
            if isCurrent(request) {
                lastFailure = .fullScreen
                Self.log.notice("Snapping \(name, privacy: .public): the window says it's full screen")
            }
            return nil
        }
        guard isCurrent(request) else { return nil }
        let target = Self.snapFrame(in: area)
        let access = access
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let work = Task {
            try await WindowSnapOperation.run(target: target, avoiding: avoiding, resize: { frame in
                let ax = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
                await access.resize(handle, to: ax)
            }, move: { frame in
                await access.move(handle, to: CGPoint(x: frame.minX, y: mainHeight - frame.maxY))
            }, read: {
                guard let ax = await access.frame(handle) else { return nil }
                return CGRect(x: ax.minX, y: mainHeight - ax.maxY, width: ax.width, height: ax.height)
            }, log: { line in
                Self.log.notice("Snapping \(name, privacy: .public): \(line, privacy: .public)")
            })
        }
        pending = (request, work)
        defer { if pending?.id == request { pending = nil } }
        let settled = try? await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        guard isCurrent(request) else { return nil }
        guard let placement = settled else {
            lastFailure = .didNotMove
            return nil
        }
        let actual = placement.frame, result = placement.result
        snapped.removeAll { CFEqual($0.handle.element, handle.element) }
        snapped.append(Remembered(handle: handle, processID: processID, frame: actual, area: area, avoiding: avoiding, result: result))
        snappedApps.insert(processID)
        return result
    }

    /// Both coordinate systems use the main display's top edge as their reference.
    private static func accessibilityFrame(from frame: CGRect) -> CGRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

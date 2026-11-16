import CoreGraphics

/// One cancellable placement, including its fallback. A newer area or a recording start cancels both
/// resize retries and position retries, so an obsolete operation cannot move a window afterward.
enum WindowSnapOperation {
    struct Placement: Sendable {
        let frame: CGRect
        let result: WindowSnapResult
    }

    /// - Parameter log: What was asked and what the window did, a line a step, for finding out why one
    ///   didn't fill the area.
    static func run(target: CGRect, avoiding: [CGRect],
                    resize: @Sendable (CGRect) async -> Void,
                    move: @Sendable (CGRect) async -> Void,
                    read: @Sendable () async -> CGRect?,
                    log: @Sendable (String) -> Void = { _ in },
                    pause: @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(80)) }) async throws -> Placement? {
        func text(_ frame: CGRect) -> String {
            "\(Int(frame.width))×\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY))"
        }
        log("asked for \(text(target)); the window is \((await read()).map(text) ?? "unreadable")")
        // Resolve the size before sending any position writes. A constrained window must not jump to
        // the area's corner while resizing, then jump again to its eventual centered placement.
        guard var actual = try await WindowResizeVerification.settle(to: target, resize: resize, read: read,
                                                                     matching: .size, pause: pause) else {
            log("its frame couldn't be read after resizing")
            return nil
        }
        log("resized in place: \(text(actual))")
        // A window can be held smaller by where it is: it can't be made bigger than the display it's on, and
        // some apps won't grow past the edge of the screen from where they sit. So one that stays too small
        // is moved to the area and asked again before it's called too small (found with a window from
        // a 1,440 pt wide display, then Xcode).
        if WindowFit.isSmaller(actual.size, than: target.size) {
            try Task.checkCancellation()
            // Its upper left to the area's, where it would end up if it grows.
            await move(CGRect(x: target.minX, y: target.maxY - actual.height, width: actual.width, height: actual.height))
            if let regrown = try await WindowResizeVerification.settle(to: target, resize: resize, read: read,
                                                                       matching: .size, pause: pause) {
                actual = regrown
            }
            log("still smaller, so moved to the area and resized again: \(text(actual))")
        }
        // A late resize can finish during the position check. Recompute the fallback once at that new
        // size instead of misreporting a window that did move as immovable.
        for _ in 0..<2 {
            try Task.checkCancellation()
            let fallback = WindowFallbackPlacement(size: actual.size, in: target, avoiding: avoiding)
            let destination = WindowFit.fit(result: actual.size, area: target.size) == .fits ? target : fallback.frame
            guard let observed = try await WindowResizeVerification.settle(to: destination,
                resize: move, read: read, pause: pause) else { return nil }
            actual = observed
            if WindowFit.fills(actual, area: destination) {
                let fit = WindowFit.fit(result: actual.size, area: target.size)
                log("placed: \(text(actual)), \(fit == .fits ? "filling the area" : "not filling it (\(fit))")")
                return Placement(frame: actual, result: fit == .fits ? .filled
                    : .placed(fit: fit, frame: actual, placement: fallback.kind))
            }
        }
        log("gave up: the window didn't reach its place, last seen \(text(actual))")
        return nil
    }
}

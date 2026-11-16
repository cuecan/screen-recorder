import CoreGraphics
import Foundation
import Testing
@testable import RecorderKit

struct WindowSnapOperationTests {
    let target = CGRect(x: 100, y: 200, width: 1_000, height: 800)

    @Test func aConstrainedWindowIsPlacedAndItsPositionIsAllowedToSettle() async throws {
        let window = WindowDriver(size: CGSize(width: 1_200, height: 900))
        let placed = try await WindowSnapOperation.run(target: target, avoiding: [],
            resize: { await window.resize($0) }, move: { await window.move($0) }, read: { await window.read() }, pause: {})
        let result = try #require(placed)
        #expect(result.frame.minX == target.minX && result.frame.maxY == target.maxY)
        guard case .placed(_, _, .upperLeft) = result.result else { Issue.record("The oversized window must stay upper-left"); return }
        #expect(await window.resizeRequests == 3)
        #expect(await window.moveRequests > 0)
    }

    @Test func aSmallerWindowMovesAwayFromTheCameraWithoutChangingItsSize() async throws {
        let window = WindowDriver(size: CGSize(width: 500, height: 400))
        let camera = CGRect(x: 750, y: 200, width: 350, height: 800)
        let placed = try await WindowSnapOperation.run(target: target, avoiding: [camera],
            resize: { await window.resize($0) }, move: { await window.move($0) }, read: { await window.read() }, pause: {})
        let result = try #require(placed)
        #expect(result.frame.size == CGSize(width: 500, height: 400))
        #expect(!camera.intersects(result.frame))
        #expect(target.contains(result.frame))
        // It's tried at the area's corner first, in case where it was is what held it small.
        #expect(await window.moveTargets == [CGRect(x: target.minX, y: target.maxY - 400, width: 500, height: 400), result.frame])
    }

    @Test func aResizableWindowChecksItsSizeInPlaceThenMovesOnce() async throws {
        let window = WindowDriver(size: CGSize(width: 1_200, height: 900), acceptsSize: true)
        let placed = try await WindowSnapOperation.run(target: target, avoiding: [],
            resize: { await window.resize($0) }, move: { await window.move($0) }, read: { await window.read() }, pause: {})
        let result = try #require(placed)
        #expect(result.frame == target)
        #expect(result.result == .filled)
        #expect(await window.resizeRequests == 1)
        #expect(await window.moveTargets == [target])
        #expect(await window.originsWhileResizing == [.zero])
    }

    @Test func aWindowHeldSmallerByWhereItIsIsMovedToTheAreaAndAskedAgain() async throws {
        // Where it starts it can't get wider than 700; once its corner is at the area's it can.
        let window = WindowDriver(size: CGSize(width: 600, height: 400), widestBeforeMoving: 700)
        let lines = Lines()
        let placed = try await WindowSnapOperation.run(target: target, avoiding: [],
            resize: { await window.resize($0) }, move: { await window.move($0) }, read: { await window.read() },
            log: { lines.add($0) }, pause: {})
        let result = try #require(placed)
        #expect(result.result == .filled)
        #expect(result.frame == target)
        #expect(await window.moveTargets.first == CGRect(x: target.minX, y: target.minY, width: 700, height: 800))
        #expect(lines.all == [
            "asked for 1000×800 at 100,200; the window is 600×400 at 0,0",
            "resized in place: 700×800 at 0,0",
            "still smaller, so moved to the area and resized again: 1000×800 at 100,200",
            "placed: 1000×800 at 100,200, filling the area",
        ])
    }

    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    @Test func cancellationAlsoStopsTheFallbackPositionRetries() async throws {
        let window = WindowDriver(size: CGSize(width: 1_200, height: 900))
        let task = Task {
            try await WindowSnapOperation.run(target: target, avoiding: [],
                resize: { await window.resize($0) }, move: { await window.move($0) }, read: { await window.read() },
                pause: { if await window.moveRequests > 0 { try await Task.sleep(for: .seconds(10)) } })
        }
        while await window.moveRequests == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await window.moveRequests == 1)
    }

    @Test func aLateSizeChangeRecomputesThePlacementInsteadOfReportingTheWindowAsImmovable() async throws {
        let window = WindowDriver(size: CGSize(width: 1_200, height: 900),
                                  sizeAfterFirstMove: CGSize(width: 500, height: 400))
        let placed = try await WindowSnapOperation.run(target: target, avoiding: [],
            resize: { await window.resize($0) }, move: { await window.move($0) }, read: { await window.read() }, pause: {})
        let result = try #require(placed)
        #expect(result.frame == CGRect(x: target.midX - 250, y: target.midY - 200, width: 500, height: 400))
        guard case .placed(_, _, .centered) = result.result else { Issue.record("The late smaller size must be centered"); return }
    }
}

private actor WindowDriver {
    var frame: CGRect
    private(set) var resizeRequests = 0
    private(set) var moveRequests = 0
    private(set) var moveTargets: [CGRect] = []
    private(set) var originsWhileResizing: [CGPoint] = []
    private let acceptsSize: Bool
    private var sizeAfterFirstMove: CGSize?
    /// The widest it can be made until it has been moved, as on a narrower display. Nil: no such limit.
    private var widestBeforeMoving: CGFloat?
    init(size: CGSize, sizeAfterFirstMove: CGSize? = nil, acceptsSize: Bool = false, widestBeforeMoving: CGFloat? = nil) {
        self.widestBeforeMoving = widestBeforeMoving
        frame = CGRect(origin: .zero, size: size)
        self.sizeAfterFirstMove = sizeAfterFirstMove
        self.acceptsSize = acceptsSize
    }
    func resize(_ target: CGRect) {
        resizeRequests += 1
        if acceptsSize { frame.size = target.size }
        if let widestBeforeMoving { frame.size = CGSize(width: moveRequests > 0 ? target.width : min(target.width, widestBeforeMoving), height: target.height) }
        originsWhileResizing.append(frame.origin)
    }
    func move(_ target: CGRect) {
        moveRequests += 1
        moveTargets.append(target)
        if let sizeAfterFirstMove { frame.size = sizeAfterFirstMove; self.sizeAfterFirstMove = nil }
        frame.origin = target.origin
    }
    func read() -> CGRect? { frame }
}

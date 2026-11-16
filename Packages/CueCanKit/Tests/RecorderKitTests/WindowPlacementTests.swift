import CoreGraphics
import Foundation
import Testing
@testable import RecorderKit

struct WindowPlacementTests {
    let area = CGRect(x: 100, y: 200, width: 1_000, height: 800)

    @Test func aSmallerWindowStaysCenteredWhenTheCameraDoesNotCoverIt() {
        let size = CGSize(width: 400, height: 300)
        let result = WindowFallbackPlacement(size: size, in: area)
        #expect(result.frame == CGRect(x: 400, y: 450, width: 400, height: 300))
        #expect(result.kind == .centered)
        let cornerCamera = CGRect(x: 900, y: 200, width: 200, height: 200)
        #expect(WindowFallbackPlacement(size: size, in: area, avoiding: [cornerCamera]) == result)
    }

    @Test func centeringMovesOnlyAsFarAsNeededToAvoidTheFacecam() {
        let camera = CGRect(x: 750, y: 200, width: 350, height: 800)
        let placement = WindowFallbackPlacement(size: CGSize(width: 500, height: 400), in: area, avoiding: [camera])
        #expect(area.contains(placement.frame))
        #expect(!camera.intersects(placement.frame))
        #expect(placement.frame.midY == area.midY)
        #expect(placement.frame.maxX == camera.minX - 8)
        let left = CGRect(x: 100, y: 200, width: 350, height: 800)
        let other = WindowFallbackPlacement(size: placement.frame.size, in: area, avoiding: [left])
        #expect(other.frame.minX == left.maxX + 8)
        #expect(other.frame.midY == area.midY)
    }

    @Test func bothOutputsAndUnavoidableOverlapStayInsideTheArea() {
        let cameras = [CGRect(x: 100, y: 200, width: 350, height: 200), CGRect(x: 800, y: 800, width: 300, height: 200)]
        let placement = WindowFallbackPlacement(size: CGSize(width: 600, height: 500), in: area, avoiding: cameras)
        #expect(area.contains(placement.frame))
        #expect(cameras.allSatisfy { !placement.frame.intersects($0) })
        let large = WindowFallbackPlacement(size: CGSize(width: 950, height: 750), in: area, avoiding: cameras)
        #expect(area.contains(large.frame))
    }

    @Test(arguments: [CGSize(width: 1_200, height: 500), CGSize(width: 500, height: 900), CGSize(width: 1_200, height: 900)])
    func anyOversizedDimensionPinsTheUpperLeft(size: CGSize) {
        let placement = WindowFallbackPlacement(size: size, in: area)
        #expect(placement.kind == .upperLeft)
        #expect(placement.frame.minX == area.minX)
        #expect(placement.frame.maxY == area.maxY)
        #expect(placement.frame.size == size)
    }

    @Test func aSlowResizeIsNotReportedAsAMinimumSize() async throws {
        let delayed = ResizeFixture(frames: [CGRect(x: 0, y: 0, width: 1_200, height: 900), area])
        let result = try await WindowResizeVerification.settle(to: area,
            resize: { await delayed.resize($0) }, read: { await delayed.read() }, pause: {})
        #expect(result == area)
        #expect(await delayed.writes == 1)
    }

    @Test func aResizeGetsRetriedBeforeAConstraintIsReported() async throws {
        let constrained = CGRect(x: 100, y: 200, width: 1_200, height: 800)
        let delayed = ResizeFixture(frames: [constrained, constrained, constrained, area])
        let result = try await WindowResizeVerification.settle(to: area,
            resize: { await delayed.resize($0) }, read: { await delayed.read() }, pause: {})
        #expect(result == area)
        #expect(await delayed.writes == 2)
        let fixed = ResizeFixture(frames: [constrained])
        #expect(try await WindowResizeVerification.settle(to: area,
            resize: { await fixed.resize($0) }, read: { await fixed.read() }, pause: {}) == constrained)
        #expect(await fixed.writes == 3)
    }

    @Test func cancellationPreventsAQueuedRetry() async throws {
        let delayed = ResizeFixture(frames: [area])
        let task = Task { try await WindowResizeVerification.settle(to: area,
            resize: { await delayed.resize($0) }, read: { await delayed.read() },
            pause: { try await Task.sleep(for: .seconds(10)) }) }
        while await delayed.writes == 0 { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await delayed.writes == 1)
    }
}

private actor ResizeFixture {
    var frames: [CGRect]
    private(set) var writes = 0
    init(frames: [CGRect]) { self.frames = frames }
    func resize(_ target: CGRect) { writes += 1 }
    func read() -> CGRect? { frames.count > 1 ? frames.removeFirst() : frames.first }
}

import Foundation
import Testing
@testable import ProjectKit

struct ExportQueueTests {
    @Test func stoppingAndDuplicateCallbacksCannotPublishNewFiles() throws {
        var queue = ExportQueue()
        let added = queue.enqueue(title: "Video", items: [.video(.landscape), .transcript])
        let id = try #require(added)
        let started = queue.startNext()
        let attempt = try #require(started)
        #expect(queue.accepts(.video(.landscape), for: attempt))
        queue.complete(.video(.landscape), files: [], for: attempt)
        #expect(!queue.accepts(.video(.landscape), for: attempt))
        #expect(queue.accepts(.transcript, for: attempt))
        queue.stop(id)
        #expect(!queue.accepts(.transcript, for: attempt))
        queue.finish(.cancelled, for: attempt)
        #expect(!queue.accepts(.transcript, for: attempt))
    }

    @Test func preparationIsVisibleWithoutInventingAProgressFraction() throws {
        var queue = ExportQueue()
        _ = queue.enqueue(title: "Video", items: [.video(.landscape)])
        let started = queue.startNext()
        let attempt = try #require(started)
        queue.prepare(.video(.landscape), for: attempt)
        #expect(queue.entries[0].job.rows[0].state == .preparing)
        queue.update(.video(.landscape), progress: 0.4, for: attempt)
        queue.prepare(.video(.landscape), for: attempt)
        #expect(queue.entries[0].job.rows[0].state == .running(0.4))
    }

    @Test func exportsAreReservedSeriallyAndOldCallbacksCannotReleaseTheNextOne() throws {
        var queue = ExportQueue()
        let firstAdded = queue.enqueue(title: "First", items: [.video(.landscape)])
        let firstID = try #require(firstAdded)
        let secondAdded = queue.enqueue(title: "Second", items: [.handoff])
        let secondID = try #require(secondAdded)
        let firstStart = queue.startNext()
        let first = try #require(firstStart)
        #expect(first.entry == firstID)
        let duplicate = queue.startNext()
        #expect(duplicate == nil)
        queue.finish(.success, for: first)
        let secondStart = queue.startNext()
        let second = try #require(secondStart)
        #expect(second.entry == secondID)
        queue.update(.handoff, progress: 1, for: first)
        queue.finish(.failed("Late callback"), for: first)
        #expect(queue.active == second)
        #expect(queue.entries[1].job.phase == .running)
        #expect(queue.entries[1].job.rows[0].state == .waiting)
    }

    @Test func cancellingQueuedWorkDoesNotInterruptTheRendererAndStoppingWaitsForCleanup() throws {
        var queue = ExportQueue()
        let firstAdded = queue.enqueue(title: "First", items: [.video(.landscape), .video(.vertical)])
        let firstID = try #require(firstAdded)
        let secondAdded = queue.enqueue(title: "Second", items: [.handoff])
        let secondID = try #require(secondAdded)
        let started = queue.startNext()
        let first = try #require(started)
        let cancelQueued = queue.stop(secondID)
        #expect(!cancelQueued)
        #expect(queue.entries[1].job.phase == .finished(.cancelled))
        let file = URL(filePath: "/tmp/finished-video.mp4")
        queue.complete(.video(.landscape), files: [file], for: first)
        let cancelRunning = queue.stop(firstID)
        #expect(cancelRunning)
        #expect(queue.entries[0].job.phase == .stopping)
        let nextWhileStopping = queue.startNext()
        #expect(nextWhileStopping == nil)
        queue.finish(.cancelled, for: first)
        #expect(queue.entries[0].job.rows[0].files == [file])
        #expect(queue.active == nil)
        let nextAfterStopping = queue.startNext()
        #expect(nextAfterStopping == nil)
    }

    @Test func clearingFinishedKeepsTheActiveAndQueuedExports() throws {
        var queue = ExportQueue()
        _ = queue.enqueue(title: "Done", items: [.transcript])
        let firstStart = queue.startNext()
        let first = try #require(firstStart)
        queue.finish(.success, for: first)
        _ = queue.enqueue(title: "Running", items: [.handoff])
        _ = queue.enqueue(title: "Queued", items: [.handoff])
        let secondStart = queue.startNext()
        let second = try #require(secondStart)
        queue.clearFinished()
        #expect(queue.entries.map(\.title) == ["Running", "Queued"])
        queue.finish(.success, for: second)
        let thirdStart = queue.startNext()
        let third = try #require(thirdStart)
        #expect(third.entry == queue.entries[1].id)
    }
}

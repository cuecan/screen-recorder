import Foundation
import Testing
@testable import ProjectKit

struct WorkQueueTests {
    let first = URL(filePath: "/tmp/first")
    let second = URL(filePath: "/tmp/second")

    @Test func settingsChangedDuringProcessingCauseExactlyOneFollowUp() throws {
        var queue = ProcessingQueue()
        queue.request(first)
        let attemptValue = queue.startNext()
        let attempt = try #require(attemptValue)
        queue.request(first)
        queue.request(first)
        queue.request(second)
        #expect({ queue.startNext() }() == nil)
        queue.finish(attempt, problem: "Old settings failed")
        let otherValue = queue.startNext()
        let other = try #require(otherValue)
        #expect(other.project == second)
        queue.finish(other, problem: nil)
        let retryValue = queue.startNext()
        let retry = try #require(retryValue)
        #expect(retry.project == first)
        queue.progress("Late old result", for: attempt)
        queue.finish(attempt, problem: "Old error")
        #expect(queue.states[first] == .running(retry, message: "Starting"))
        queue.finish(retry, problem: nil)
        #expect({ queue.startNext() }() == nil)
        #expect(queue.states.isEmpty)
    }

    @Test func failuresCanBeRetriedAndQueuedRequestsCoalesce() throws {
        var queue = ProcessingQueue()
        queue.request(first)
        queue.request(first)
        let attemptValue = queue.startNext()
        let attempt = try #require(attemptValue)
        queue.finish(attempt, problem: "Disk full")
        #expect(queue.states[first] == .failed("Disk full"))
        queue.request(first)
        let retryValue = queue.startNext()
        let retry = try #require(retryValue)
        queue.finish(retry, problem: nil)
        #expect({ queue.startNext() }() == nil)
    }

    @Test func thumbnailWorkerIsReservedBeforeAnyTaskStarts() throws {
        var queue = ThumbnailQueue()
        queue.request(first, revision: 1)
        let firstRequestValue = queue.startNext()
        let firstRequest = try #require(firstRequestValue)
        queue.request(second, revision: 1)
        #expect({ queue.startNext() }() == nil)
        #expect({ queue.finish(firstRequest) }())
        #expect({ queue.startNext() }()?.project == second)
    }

    @Test func forgottenAndSupersededThumbnailsCannotPublish() throws {
        var queue = ThumbnailQueue()
        queue.request(first, revision: 1)
        let oldValue = queue.startNext()
        let old = try #require(oldValue)
        queue.request(first, revision: 2)
        #expect(!{ queue.finish(old) }())
        let newerValue = queue.startNext()
        let newer = try #require(newerValue)
        queue.forget(first)
        queue.request(first, revision: 2)
        #expect(!{ queue.finish(newer) }(), "Even the same revision requested after forget has a new identity")
        let restoredValue = queue.startNext()
        let restored = try #require(restoredValue)
        #expect({ queue.finish(restored) }())
        #expect(!{ queue.finish(old) }())
        #expect(queue.hasCompleted(first, revision: 2))
    }
}

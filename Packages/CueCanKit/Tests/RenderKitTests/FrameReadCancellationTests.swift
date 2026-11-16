import Foundation
import Testing
@testable import RenderKit

struct FrameReadCancellationTests {
    @Test func cancellationDuringPreparationDefersTeardownAndPreventsExtraction() async throws {
        let calls = Calls()
        let entered = AsyncStream<Void>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let cancellation = FrameReadCancellation(start: {
            calls.started()
            entered.continuation.yield()
            release.wait()
        }, cancel: { calls.cancelled() })
        let preparation = Task.detached { try cancellation.start() }
        defer { release.signal(); entered.continuation.finish() }
        for await _ in entered.stream { break }
        cancellation.cancel()
        #expect(cancellation.isCancelled)
        #expect(calls.cancellations == 0, "Native teardown must not overlap reader preparation.")
        release.signal()
        do {
            try await preparation.value
            Issue.record("Cancelled preparation must not proceed to extraction.")
        } catch is CancellationError {
        }
        #expect(calls.starts == 1 && calls.cancellations == 1)
        #expect(throws: CancellationError.self) { try cancellation.beginRead() }
        cancellation.cancel()
        #expect(calls.cancellations == 1)
    }

    @Test func finishingAnUncancelledExtractionLeavesCleanupToTheCaller() throws {
        let calls = Calls()
        let cancellation = FrameReadCancellation(start: { calls.started() }, cancel: { calls.cancelled() })
        try cancellation.start()
        try cancellation.beginRead()
        cancellation.finishRead()
        #expect(!cancellation.isCancelled)
        #expect(calls.cancellations == 0)
        cancellation.cancel()
        #expect(calls.cancellations == 1)
    }

    @Test func cancellationDuringExtractionDefersTeardownUntilTheSampleReturns() throws {
        let calls = Calls()
        let cancellation = FrameReadCancellation(start: { calls.started() }, cancel: { calls.cancelled() })
        try cancellation.start()
        try cancellation.beginRead()
        cancellation.cancel()
        cancellation.cancel()
        #expect(cancellation.isCancelled)
        #expect(calls.cancellations == 0, "Native teardown must not overlap the provider's extraction.")
        cancellation.finishRead()
        #expect(calls.cancellations == 1)
        cancellation.cancel()
        cancellation.finishRead()
        #expect(calls.cancellations == 1)
        #expect(throws: CancellationError.self) { try cancellation.beginRead() }
    }

    @Test func cancellationBetweenPreparationAndExtractionPreventsTheRead() throws {
        let calls = Calls()
        let cancellation = FrameReadCancellation(start: { calls.started() }, cancel: { calls.cancelled() })
        try cancellation.start()
        cancellation.cancel()
        #expect(calls.cancellations == 1)
        #expect(throws: CancellationError.self) { try cancellation.beginRead() }
        cancellation.cancel()
        #expect(calls.cancellations == 1)
    }

    @Test func cancellationBeforePreparationNeverStartsOrCancelsANativeReader() {
        let calls = Calls()
        let cancellation = FrameReadCancellation(start: { calls.started() }, cancel: { calls.cancelled() })
        cancellation.cancel()
        #expect(throws: CancellationError.self) { try cancellation.start() }
        #expect(calls.starts == 0 && calls.cancellations == 0)
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var startCount = 0
        private var cancelCount = 0
        var starts: Int { lock.withLock { startCount } }
        var cancellations: Int { lock.withLock { cancelCount } }
        func started() { lock.withLock { startCount += 1 } }
        func cancelled() { lock.withLock { cancelCount += 1 } }
    }
}

import Foundation
import Testing
@testable import RenderKit

struct FrameReadTaskTests {
    @Test func blockedNativeCallsCannotStarveTheirCallerDeadlines() async throws {
        let workers = min(32, ProcessInfo.processInfo.activeProcessorCount + 1)
        let limit = FrameReadLimit(capacity: workers)
        let natives = (0..<workers).map { _ in NativeBlock(phase: .preparing) }
        let rescue = DispatchWorkItem { for native in natives { native.release() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: rescue)
        defer { rescue.cancel(); for native in natives { native.release() } }
        let requests = natives.map { native in
            Task { try await FrameReadTask.run(limit: limit, timeout: .seconds(1)) { try native.extract(hasStopped: $0) } }
        }
        for native in natives { await native.waitUntilEntered() }
        for request in requests { await #expect(throws: RenderError.self) { try await request.value } }
        #expect(limit.activeCount == workers)
        #expect(natives.allSatisfy { $0.cancellations == 0 })
        for native in natives { native.release() }
        try await waitUntilReleased(limit)
    }

    @Test func ordinaryReadsQueueAndACancelledWaiterNeverStartsNativeWork() async throws {
        let limit = FrameReadLimit(capacity: 1)
        let native = NativeBlock(phase: .extracting)
        let safety = Task.detached { try? await Task.sleep(for: .seconds(5)); native.release() }
        defer { native.release(); safety.cancel() }
        let first = Task { try await FrameReadTask.run(limit: limit) { try native.extract(hasStopped: $0) } }
        await native.waitUntilEntered()
        let second = Task { try await FrameReadTask.run(limit: limit) { _ in 42 } }
        let deadline = ContinuousClock.now + .seconds(2)
        while limit.queuedCount == 0, ContinuousClock.now < deadline { await Task.yield() }
        try #require(limit.queuedCount == 1)
        second.cancel()
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(limit.queuedCount == 0 && limit.activeCount == 1)
        let third = Task { try await FrameReadTask.run(limit: limit) { _ in 43 } }
        native.release()
        #expect(try await first.value == 7)
        #expect(try await third.value == 43)
        try await waitUntilReleased(limit)
    }

    @Test(arguments: [NativeBlock.Phase.preparing, .extracting])
    func timeoutReturnsWhileNativeWorkRemainsBounded(phase: NativeBlock.Phase) async throws {
        let limit = FrameReadLimit(capacity: 1)
        let native = NativeBlock(phase: phase)
        let safety = Task.detached { try? await Task.sleep(for: .seconds(5)); native.release() }
        defer { native.release(); safety.cancel() }
        let request = Task { try await FrameReadTask.run(limit: limit, timeout: .milliseconds(20)) { try native.extract(hasStopped: $0) } }
        await native.waitUntilEntered()
        await #expect(throws: RenderError.self) { try await request.value }
        #expect(limit.activeCount == 1, "Returning to the caller must not release a native worker that is still blocked.")
        #expect(native.cancellations == 0, "Timeout must not tear down underneath native work.")
        await #expect(throws: FrameReadTask.CapacityError.self) { try await FrameReadTask.run(limit: limit) { _ in 42 } }
        native.release()
        try await waitUntilReleased(limit)
        #expect(native.cancellations == 1)
        #expect(try await FrameReadTask.run(limit: limit) { _ in 42 } == 42)
    }

    @Test func cancellationReturnsBeforeAnInFlightExtractionEnds() async throws {
        let limit = FrameReadLimit(capacity: 1)
        let native = NativeBlock(phase: .extracting)
        let safety = Task.detached { try? await Task.sleep(for: .seconds(5)); native.release() }
        defer { native.release(); safety.cancel() }
        let request = Task { try await FrameReadTask.run(limit: limit) { try native.extract(hasStopped: $0) } }
        await native.waitUntilEntered()
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(limit.activeCount == 1 && native.cancellations == 0)
        native.release()
        try await waitUntilReleased(limit)
        #expect(native.cancellations == 1)
    }

    @Test func completionBeforeRegistrationKeepsTheFirstResult() async throws {
        let completion = FrameReadCompletion<Int>()
        completion.finish(.success(7))
        completion.finish(.failure(CancellationError()))
        #expect(try await completion.value() == 7)
    }

    @Test func racingCompletionsResumeTheWaiterOnce() async throws {
        for _ in 0..<100 {
            let completion = FrameReadCompletion<Int>()
            let waiter = Task { try await completion.value() }
            await withTaskGroup(of: Void.self) { group in
                for value in 0..<8 { group.addTask { completion.finish(.success(value)) } }
            }
            #expect((0..<8).contains(try await waiter.value))
        }
    }

    private func waitUntilReleased(_ limit: FrameReadLimit) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while limit.activeCount != 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(limit.activeCount == 0)
    }

    final class NativeBlock: @unchecked Sendable {
        enum Phase: Sendable { case preparing, extracting }
        let phase: Phase
        private let entered = AsyncStream<Void>.makeStream()
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var cancelled = 0
        var cancellations: Int { lock.withLock { cancelled } }
        init(phase: Phase) { self.phase = phase }
        func release() { entered.continuation.finish(); semaphore.signal() }
        func waitUntilEntered() async { for await _ in entered.stream { break } }
        private func block() { entered.continuation.yield(); semaphore.wait() }

        func extract(hasStopped: @Sendable () -> Bool) throws -> Int {
            let cancellation = FrameReadCancellation(start: {
                if self.phase == .preparing { self.block() }
            }, cancel: { self.lock.withLock { self.cancelled += 1 } })
            defer { cancellation.cancel() }
            try cancellation.start()
            guard !hasStopped() else { throw CancellationError() }
            try cancellation.beginRead()
            defer { cancellation.finishRead() }
            if phase == .extracting { block() }
            guard !hasStopped() else { throw CancellationError() }
            return 7
        }
    }
}

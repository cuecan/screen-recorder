import Foundation

/// A caller can stop waiting without tearing down native extraction. The slot stays occupied until
/// the worker and its cleanup actually finish, so abandoned decoders cannot accumulate without bound.
enum FrameReadTask {
    private static let executor = FrameReadExecutor()
    static func run<Value: Sendable>(limit: FrameReadLimit, timeout: Duration = .seconds(10),
                                    read: @escaping @Sendable (_ hasStopped: @escaping @Sendable () -> Bool) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let completion = FrameReadCompletion<Value>()
        let id = UUID()
        let priority = Task.currentPriority
        return try await withTaskCancellationHandler {
            let deadline = Task.detached {
                do { try await Task.sleep(for: timeout) } catch { return }
                if completion.finish(.failure(RenderError.exportFailed("Reading the preview took too long. Try again."))) { limit.abandon(id) }
            }
            defer { deadline.cancel() }
            if !completion.isFinished {
                limit.schedule(id, hasStopped: { completion.isFinished }, start: {
                    Task.detached(executorPreference: executor, priority: priority) {
                        defer { limit.release(id) }
                        guard !completion.isFinished else { return }
                        do { completion.finish(.success(try await read { completion.isFinished })) }
                        catch { completion.finish(.failure(error)) }
                    }
                }, reject: { completion.finish(.failure(CapacityError())) })
            }
            let value = try await completion.value()
            try Task.checkCancellation()
            return value
        } onCancel: {
            if completion.finish(.failure(CancellationError())) { limit.abandon(id) }
        }
    }

    struct CapacityError: LocalizedError {
        var errorDescription: String? { "The preview is busy finishing earlier frames. Try again shortly." }
    }
}

/// Includes workers whose caller has timed out or cancelled, until native extraction and cleanup return.
final class FrameReadLimit: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private struct Pending {
        let id: UUID
        let start: @Sendable () -> Void
        let reject: @Sendable () -> Void
    }
    private var active: [UUID: Bool] = [:]
    private var pending: [Pending] = []

    init(capacity: Int) { precondition(capacity > 0); self.capacity = capacity }
    var activeCount: Int { lock.withLock { active.count } }
    var queuedCount: Int { lock.withLock { pending.count } }

    func schedule(_ id: UUID, hasStopped: @Sendable () -> Bool,
                  start: @escaping @Sendable () -> Void, reject: @escaping @Sendable () -> Void) {
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            guard !hasStopped() else { return nil }
            if active.count < capacity {
                active[id] = false
                return start
            }
            if active.values.allSatisfy({ $0 }) { return reject }
            pending.append(Pending(id: id, start: start, reject: reject))
            return nil
        }
        action?()
    }

    func abandon(_ id: UUID) {
        let rejected = lock.withLock { () -> [@Sendable () -> Void] in
            if active[id] != nil { active[id] = true }
            else { pending.removeAll { $0.id == id } }
            guard active.count == capacity, active.values.allSatisfy({ $0 }) else { return [] }
            let rejected = pending.map(\.reject)
            pending.removeAll()
            return rejected
        }
        for reject in rejected { reject() }
    }

    func release(_ id: UUID) {
        let next = lock.withLock { () -> (@Sendable () -> Void)? in
            precondition(active.removeValue(forKey: id) != nil)
            guard !pending.isEmpty else { return nil }
            let next = pending.removeFirst()
            active[next.id] = false
            return next.start
        }
        next?()
    }
}

/// Reader preparation is synchronous. Keep it off Swift's cooperative pool so even several blocked
/// native calls cannot prevent timeout tasks or their callers from running.
private final class FrameReadExecutor: TaskExecutor {
    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let qos: DispatchQoS.QoSClass
        if job.priority.rawValue >= TaskPriority.high.rawValue { qos = .userInitiated }
        else if job.priority.rawValue >= TaskPriority.medium.rawValue { qos = .default }
        else if job.priority.rawValue >= TaskPriority.low.rawValue { qos = .utility }
        else { qos = .background }
        DispatchQueue.global(qos: qos).async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
    }
}

/// One result wins between completion, timeout and cancellation, before or after a waiter registers.
final class FrameReadCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?

    var isFinished: Bool { lock.withLock { result != nil } }

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let ready = lock.withLock { () -> Result<Value, Error>? in
                if let result { return result }
                precondition(self.continuation == nil)
                self.continuation = continuation
                return nil as Result<Value, Error>?
            }
            if let ready { continuation.resume(with: ready) }
        }
    }

    @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
        let finished = lock.withLock { () -> (Bool, CheckedContinuation<Value, Error>?) in
            guard self.result == nil else { return (false, nil) }
            self.result = result
            defer { self.continuation = nil }
            return (true, self.continuation)
        }
        finished.1?.resume(with: result)
        return finished.0
    }
}

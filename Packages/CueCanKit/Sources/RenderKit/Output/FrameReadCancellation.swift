import AVFoundation
import Foundation

/// Records cancellation during native preparation or extraction and tears down only between calls.
/// An async output provider can still be extracting a sample while `next()` is suspended; cancelling
/// its reader then can destroy the visual context the extraction is using.
/// This coordinator cannot interrupt a stuck native call. VERIFY whether the async provider honors
/// task cancellation; callers need a separate completion gate and must not wait on teardown.
final class FrameReadCancellation: @unchecked Sendable {
    // These closures stay inside the coordinator; its state prevents native calls from overlapping.
    private let startReader: () throws -> Void
    private let cancelReader: () -> Void
    private let lock = NSLock()
    private enum State { case waiting, starting, ready, reading, cancelledDuringStart, cancelledDuringRead, cancelled }
    private var state = State.waiting

    init(reader: AVAssetReader) {
        startReader = { try reader.start() }
        cancelReader = { reader.cancelReading() }
    }

    init(start: @escaping @Sendable () throws -> Void, cancel: @escaping @Sendable () -> Void) {
        startReader = start
        cancelReader = cancel
    }

    /// For the tests: nothing else needs to ask, since a cancelled read fails in `beginRead()`.
    var isCancelled: Bool {
        lock.withLock {
            switch state {
            case .cancelledDuringStart, .cancelledDuringRead, .cancelled: true
            default: false
            }
        }
    }

    /// AVFoundation prepares track extraction synchronously inside start. Cancellation records intent
    /// during that interval; the starting task cancels after preparation returns. Never hold the lock
    /// across AVFoundation's work: a gesture cancelled on the main actor must not wait for a cold start.
    func start() throws {
        let starts = lock.withLock {
            guard case .waiting = state else { return false }
            state = .starting
            return true
        }
        guard starts else { throw CancellationError() }
        do {
            try startReader()
        } catch {
            lock.withLock { state = .cancelled }
            throw error
        }
        let cancelled = lock.withLock {
            if case .cancelledDuringStart = state {
                state = .cancelled
                return true
            }
            state = .ready
            return false
        }
        if cancelled { cancelReader(); throw CancellationError() }
    }

    /// Reserve extraction before calling the provider, so cancellation cannot tear down underneath it.
    func beginRead() throws {
        let reads = lock.withLock {
            guard case .ready = state else { return false }
            state = .reading
            return true
        }
        guard reads else { throw CancellationError() }
    }

    func finishRead() {
        let cancelsReader = lock.withLock {
            switch state {
            case .cancelledDuringRead: state = .cancelled; return true
            case .reading: state = .ready; return false
            default: return false
            }
        }
        if cancelsReader { cancelReader() }
    }

    func cancel() {
        let cancelsReader = lock.withLock {
            switch state {
            case .waiting: state = .cancelled; return false
            case .starting: state = .cancelledDuringStart; return false
            case .ready: state = .cancelled; return true
            case .reading: state = .cancelledDuringRead; return false
            case .cancelledDuringStart, .cancelledDuringRead, .cancelled: return false
            }
        }
        if cancelsReader { cancelReader() }
    }
}

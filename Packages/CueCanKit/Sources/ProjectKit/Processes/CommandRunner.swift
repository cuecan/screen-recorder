import Foundation
import Synchronization

/// Runs a local helper, draining both pipes while it runs and terminating it when its task is cancelled.
/// This keeps a verbose child from blocking on a full pipe, and cancellation from leaving work running.
public enum CommandRunner {
    public struct Output: Sendable {
        public let status: Int32
        public let standardOutput: String
        public let standardError: String
        public init(status: Int32, standardOutput: String, standardError: String) {
            self.status = status
            self.standardOutput = standardOutput
            self.standardError = standardError
        }
    }

    public static func run(
        executable: URL,
        arguments: [String],
        onStandardOutput: @escaping @Sendable (String) -> Void = { _ in },
        onStandardError: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Output {
        let lifecycle = Lifecycle()
        return try await withTaskCancellationHandler {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            let stdout = Drain(output.fileHandleForReading, line: onStandardOutput)
            let stderr = Drain(errors.fileHandleForReading, line: onStandardError)
            let result: Result<Int32, Error> = await withCheckedContinuation { continuation in
                process.terminationHandler = { process in
                    lifecycle.finish()
                    continuation.resume(returning: .success(process.terminationStatus))
                }
                do {
                    try lifecycle.launch(process)
                } catch {
                    continuation.resume(returning: .failure(error))
                }
                // The child has inherited its descriptors; only its exit should keep readers waiting.
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
            }
            let text = await stdout.value
            let errorText = await stderr.value
            try Task.checkCancellation()
            return Output(status: try result.get(), standardOutput: text, standardError: errorText)
        } onCancel: {
            lifecycle.cancel()
        }
    }

    private static func drain(_ handle: FileHandle, line: @Sendable (String) -> Void = { _ in }) -> String {
        defer { try? handle.close() }
        var all = Data()
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            // The system's own read, which returns whatever the child has written so far. FileHandle's waits
            // until it has the whole count or the pipe closes, which held every short line back to the end.
            let count = read(handle.fileDescriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            let chunk = buffer[..<count]
            all.append(contentsOf: chunk)
            pending.append(contentsOf: chunk)
            while let newline = pending.firstIndex(of: 10) {
                line(String(decoding: pending[..<newline], as: UTF8.self))
                pending.removeSubrange(...newline)
            }
        }
        if !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
        return String(decoding: all, as: UTF8.self)
    }

    /// Reads a pipe to its end on a thread of its own. A read blocks until the child writes or exits, and
    /// Swift's tasks share only as many threads as the Mac has cores: on a Mac with few cores, a few reads
    /// waiting there left no thread to launch the children they were waiting for.
    private final class Drain: Sendable {
        private struct State {
            var text: String?
            var waiter: CheckedContinuation<String, Never>?
        }
        private let state = Mutex(State())

        init(_ handle: FileHandle, line: @escaping @Sendable (String) -> Void) {
            Thread.detachNewThread { [self] in
                let text = CommandRunner.drain(handle, line: line)
                let waiter = state.withLock { state in
                    state.text = text
                    defer { state.waiter = nil }
                    return state.waiter
                }
                waiter?.resume(returning: text)
            }
        }

        var value: String {
            get async {
                await withCheckedContinuation { continuation in
                    let ready = state.withLock { state -> String? in
                        if let text = state.text { return text }
                        state.waiter = continuation
                        return nil
                    }
                    if let ready { continuation.resume(returning: ready) }
                }
            }
        }
    }

    /// Serializes cancellation with launch and exit, including cancellation before the child exists.
    private final class Lifecycle: Sendable {
        private enum State {
            case ready, running(Process), cancelled, finished
        }
        private let state = Mutex(State.ready)

        func launch(_ process: Process) throws {
            try state.withLock { state in
                guard case .ready = state else { throw CancellationError() }
                do {
                    try process.run()
                    state = .running(process)
                } catch {
                    state = .finished
                    throw error
                }
            }
        }

        func cancel() {
            state.withLock { state in
                switch state {
                case .ready: state = .cancelled
                case .running(let process):
                    process.terminate()
                    state = .cancelled
                case .cancelled, .finished: break
                }
            }
        }

        func finish() { state.withLock { $0 = .finished } }
    }
}

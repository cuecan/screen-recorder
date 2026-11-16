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
            let stdout = Task.detached { drain(output.fileHandleForReading, line: onStandardOutput) }
            let stderr = Task.detached { drain(errors.fileHandleForReading, line: onStandardError) }
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
        while let chunk = try? handle.read(upToCount: 4096), !chunk.isEmpty {
            all.append(chunk)
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                line(String(decoding: pending[..<newline], as: UTF8.self))
                pending.removeSubrange(...newline)
            }
        }
        if !pending.isEmpty { line(String(decoding: pending, as: UTF8.self)) }
        return String(decoding: all, as: UTF8.self)
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

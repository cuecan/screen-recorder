import Foundation
import Synchronization
import Testing
import ProjectKit

struct CommandRunnerTests {
    @Test func drainsBothPipesWhileTheHelperRuns() async throws {
        let output = try await CommandRunner.run(executable: URL(filePath: "/bin/sh"), arguments: [
            "-c", "/usr/bin/head -c 262144 /dev/zero; /usr/bin/head -c 262144 /dev/zero >&2",
        ])
        #expect(output.status == 0)
        #expect(output.standardOutput.utf8.count == 262144)
        #expect(output.standardError.utf8.count == 262144)
    }

    /// A helper's short lines, a download's progress say, are passed on as it writes them, not saved up
    /// until it exits.
    @Test func aLineArrivesWhileTheHelperIsStillRunning() async throws {
        let clock = ContinuousClock()
        let arrivals = Mutex<[String: ContinuousClock.Instant]>([:])
        _ = try await CommandRunner.run(executable: URL(filePath: "/bin/sh"), arguments: [
            "-c", "echo first; /bin/sleep 2; echo second",
        ], onStandardOutput: { line in
            arrivals.withLock { $0[line] = clock.now }
        })
        let times = arrivals.withLock { $0 }
        let first = try #require(times["first"]), second = try #require(times["second"])
        #expect(first.duration(to: second) > .seconds(1))
    }

    @Test func cancellationStopsTheHelper() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await CommandRunner.run(executable: URL(filePath: "/bin/sleep"), arguments: ["10"])
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("The cancelled helper returned success")
        } catch is CancellationError {
            #expect(started.duration(to: clock.now) < .seconds(3))
        }
    }

    @Test func cancellationBeforeLaunchAndLaunchFailureFinishReaders() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CommandRunner.run(executable: URL(filePath: "/bin/sleep"), arguments: ["10"])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        await #expect(throws: (any Error).self) {
            try await CommandRunner.run(executable: URL(filePath: "/nonexistent-cuecan-helper"), arguments: [])
        }
    }
}

import Foundation
import ProjectKit
import Testing
@testable import CueCan

/// The setup window's speech models row (docs/decisions.md, 93), with the helper stood in for.
@MainActor
struct SpeechModelsModelTests {
    private func lines(_ messages: [SpeechModelsMessage]) -> [String] { messages.compactMap { try? $0.line() } }

    private func model(answering answers: @escaping @Sendable ([String]) -> [SpeechModelsMessage]) -> SpeechModelsModel {
        SpeechModelsModel { arguments, line in
            let lines = answers(arguments).compactMap { try? $0.line() }
            for text in lines { line(text) }
            return CommandRunner.Output(status: 0, standardOutput: lines.joined(separator: "\n"), standardError: "")
        }
    }

    @Test func itStartsByAskingAndOffersTheDownloadWhenTheyAreMissing() async throws {
        let missing = model { _ in [.missing] }
        #expect(missing.state == .checking)
        missing.check()
        try await waitUntil { missing.state != .checking }
        #expect(missing.state == .missing)
        let here = model { _ in [.ready] }
        here.check()
        try await waitUntil { here.state != .checking }
        #expect(here.state == .downloaded)
    }

    @Test func aDownloadShowsItsProgressThenThatItIsDone() async throws {
        let model = model { $0 == ["download"] ? [.progress(0.25), .progress(0.6), .ready] : [.missing] }
        model.download()
        #expect(model.state == .downloading(0))
        try await waitUntil { model.state == .downloaded }
    }

    @Test func aFailedDownloadSaysWhyAndCanBeTriedAgain() async throws {
        let attempts = Attempts()
        let model = model { _ in attempts.next() == 1 ? [.progress(0.1), .failed("The Internet connection appears to be offline.")] : [.ready] }
        model.download()
        try await waitUntil { if case .failed = model.state { true } else { false } }
        #expect(model.state == .failed("The Internet connection appears to be offline."))
        model.download()
        try await waitUntil { model.state == .downloaded }
    }

    @Test func aHelperThatCannotRunIsAFailureNotASilentSuccess() async throws {
        let model = SpeechModelsModel { _, _ in throw CocoaError(.fileNoSuchFile) }
        model.download()
        try await waitUntil { if case .failed = model.state { true } else { false } }
    }

    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.withLock { count += 1; return count } }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        try #require(condition())
    }
}

import Foundation
import Observation
import ProjectKit

/// Runs processing on its own after a recording (docs/design.md, "How it works for the creator"):
/// transcribing, SpeechAnalyzer's second reading, the vocabulary, cleanup, and reading the screen, with
/// its text only while "Save screen text" is on (docs/decisions.md, 58).
///
/// It runs the bundled `cuecan process` in its own process, one project at a time, so Parakeet's models
/// never load into the app, and a crash there never takes a recording with it.
@Observable
final class ProcessingCenter {
    private var jobs = ProcessingQueue()
    var activity: [URL: String] { jobs.states.compactMapValues(\.activity) }
    var problems: [URL: String] {
        jobs.states.compactMapValues { if case .failed(let message) = $0 { message } else { nil } }
    }

    /// The "Save screen text" setting's key. On by default.
    nonisolated static let savesScreenTextKey = "SaveScreenText"

    nonisolated static var savesScreenText: Bool {
        UserDefaults.standard.object(forKey: savesScreenTextKey) as? Bool ?? true
    }

    /// The `cuecan` CLI inside the app bundle (docs/decisions.md, 31).
    nonisolated static var cli: URL { Bundle.main.bundleURL.appending(path: "Contents/Helpers/cuecan") }

    /// Processes everything a project still needs. Asking again while it's queued does nothing.
    func process(_ folder: ProjectFolder) {
        jobs.request(folder.url)
        runNext()
    }

    private func runNext() {
        guard let attempt = jobs.startNext() else { return }
        Task {
            let result = await Self.run(attempt.project) { line in
                Task { @MainActor in self.jobs.progress(line, for: attempt) }
            }
            jobs.finish(attempt, problem: result)
            runNext()
        }
    }

    /// Runs `cuecan process` on a project, passing each progress line on. Returns a problem, if any.
    nonisolated private static func run(_ project: URL, progress: @escaping @Sendable (String) -> Void) async -> String? {
        do {
            let output = try await CommandRunner.run(
                executable: cli,
                arguments: ["--machine", "process", project.path(percentEncoded: false)] + (savesScreenText ? [] : ["--no-screen-text"]),
                onStandardOutput: { line in
                    if case .progress(let event) = try? HelperMessage.read(line) { progress(event.message) }
                }
            )
            guard case .processed(let report) = try HelperMessage.result(in: output) else {
                throw HelperMessage.Failure("Processing returned an unexpected result.")
            }
            return report.problem
        } catch {
            return "Couldn't process the project: \(error.localizedDescription)"
        }
    }
}

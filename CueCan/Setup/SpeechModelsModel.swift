import Foundation
import Observation
import ProjectKit

/// Whether the speech models are on this Mac, and downloading them from the setup window so the first
/// take doesn't wait for them (docs/decisions.md, 93).
///
/// The app can't load the models' code, so the bundled `cuecan models` answers and downloads. A download
/// goes on if the window is closed; one cut short by quitting is picked up by the next.
@Observable
final class SpeechModelsModel {
    enum State: Equatable {
        /// Not asked yet, or asking.
        case checking
        case missing
        /// Downloading, with the fraction done.
        case downloading(Double)
        case downloaded
        case failed(String)
    }

    private(set) var state = State.checking
    @ObservationIgnored private let run: Runner
    @ObservationIgnored private var work: Task<Void, Never>?

    /// Runs `cuecan --machine models` with these arguments, passing on each line as it arrives.
    typealias Runner = @Sendable (_ arguments: [String], _ line: @escaping @Sendable (String) -> Void) async throws -> CommandRunner.Output

    init(run: @escaping Runner = { arguments, line in
        try await CommandRunner.run(executable: ProcessingCenter.cli, arguments: ["--machine", "models"] + arguments, onStandardOutput: line)
    }) {
        self.run = run
    }

    /// Asks whether the models are here. A download under way is left alone.
    func check() {
        guard work == nil else { return }
        work = Task {
            let answer = await answer(to: [])
            // A check that couldn't run offers the download, which says what's wrong if it fails too.
            state = answer == .ready ? .downloaded : .missing
            work = nil
        }
    }

    func download() {
        guard work == nil else { return }
        state = .downloading(0)
        work = Task {
            let answer = await answer(to: ["download"]) { [weak self] line in
                guard case .progress(let fraction) = try? SpeechModelsMessage.read(line) else { return }
                Task { @MainActor in self?.progressed(to: fraction) }
            }
            switch answer {
            case .ready: state = .downloaded
            case .failed(let reason): state = .failed(reason)
            case .missing, .progress: state = .failed("The download stopped before it finished.")
            }
            work = nil
        }
    }

    private func progressed(to fraction: Double) {
        // Lines can arrive after the answer; the bar only moves forward while downloading.
        guard case .downloading(let current) = state, fraction > current else { return }
        state = .downloading(fraction)
    }

    private func answer(to arguments: [String], line: @escaping @Sendable (String) -> Void = { _ in }) async -> SpeechModelsMessage {
        do {
            return SpeechModelsMessage.result(in: try await run(arguments, line))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

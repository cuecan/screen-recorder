import AudioKit
import Foundation
import Observation
import ProjectKit
import RenderKit

/// App-owned exports continue when their setup sheet, editor or projects window closes. A serial queue
/// avoids competing renderers, while each export keeps its own frozen inputs and completed files.
@Observable
final class ExportCenter {
    typealias Renderer = @Sendable (ExportPlan, @escaping @Sendable (FinishedExporter.Event) async -> Void) async throws -> ExportResult
    private(set) var queue = ExportQueue()
    /// A queued plan and the audio it owns stay together until the audio is released.
    private struct Resources {
        let plan: ExportPlan
        var audio: ExportAudioSnapshot?
    }
    @ObservationIgnored private var resources: [UUID: Resources] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var publicationProblem: String?
    @ObservationIgnored private let renderer: Renderer

    init(renderer: Renderer? = nil) { self.renderer = renderer ?? Self.render }

    var entries: [ExportQueue.Entry] { queue.entries }
    var activeCount: Int { entries.filter(\.isActive).count }

    func plan(for id: UUID) -> ExportPlan? { resources[id]?.plan }

    /// A take's media must remain in place while queued or running exports still reference it.
    func activity(for project: URL) -> String? {
        guard let entry = entries.first(where: { $0.isActive && resources[$0.id]?.plan.inputs.folder.url.pathComponents == project.pathComponents }) else { return nil }
        return entry.job.phase == .setup ? "Waiting to export \(entry.title)" : "\(entry.status) \(entry.title)"
    }

    func conflicts(for plan: ExportPlan) -> [URL] {
        let reserved = reservedOutputs
        return plan.outputURLs.filter { reserved.contains($0) || FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    func enqueue(_ plan: ExportPlan) throws {
        guard plan.existingOutputs().isEmpty else {
            throw HelperMessage.Failure("An export with this name already exists.")
        }
        let reserved = reservedOutputs
        guard reserved.isDisjoint(with: plan.outputURLs) else {
            throw HelperMessage.Failure("An export is already using this name.")
        }
        guard !plan.items.isEmpty else { return }
        let snapshot = try ExportAudioSnapshot.capture(plan.inputs)
        guard let id = queue.enqueue(title: plan.baseName, items: plan.items) else { try? snapshot.release(); return }
        resources[id] = Resources(plan: ExportPlan(inputs: snapshot.inputs, destination: plan.destination, kind: plan.kind, name: plan.baseName), audio: snapshot)
        runNext()
    }

    func stop(_ id: UUID) {
        if entries.first(where: { $0.id == id })?.job.phase == .setup {
            let warnings = releaseAudio(for: id).map { [$0] } ?? []
            queue.stop(id, warnings: warnings)
            return
        }
        if queue.stop(id) { task?.cancel() }
    }

    func clearFinished() {
        queue.clearFinished()
        let kept = Set(entries.map(\.id))
        resources = resources.filter { kept.contains($0.key) }
    }

    private var reservedOutputs: Set<URL> {
        Set(entries.filter(\.isActive).flatMap { resources[$0.id]?.plan.outputURLs ?? [] })
    }

    private func runNext() {
        guard let attempt = queue.startNext(), let plan = resources[attempt.entry]?.plan else { return }
        publicationProblem = nil
        task = Task {
            let staging = plan.destination.appending(path: ".cuecan-export-\(UUID())", directoryHint: .isDirectory)
            var outcome = ExportJob.Outcome.success
            var warnings: [String] = []
            do {
                // A queued export checks again when it reaches the front, since files may have appeared.
                guard plan.existingOutputs().isEmpty else {
                    throw HelperMessage.Failure("An export with this name already exists.")
                }
                try FileManager.default.createDirectory(at: plan.destination, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
                let staged = ExportPlan(inputs: plan.inputs, destination: staging, kind: plan.kind, name: plan.baseName)
                let result = try await renderer(staged) { event in
                    await MainActor.run {
                        guard self.queue.active == attempt else { return }
                        switch event {
                        case .preparing(let item): self.queue.prepare(item, for: attempt)
                        case .progress(let item, let fraction): self.queue.update(item, progress: fraction, for: attempt)
                        case .completed(let item, let files):
                            guard self.queue.accepts(item, for: attempt) else { return }
                            do {
                                let published = try ExportPublication.publish(files, to: plan.destination)
                                self.queue.complete(item, files: published, for: attempt)
                            } catch is CancellationError {
                                self.queue.stop(attempt.entry)
                                self.task?.cancel()
                            } catch {
                                self.publicationProblem = error.localizedDescription
                                self.queue.stop(attempt.entry)
                                self.task?.cancel()
                            }
                        }
                    }
                }
                try Task.checkCancellation()
                warnings = result.warnings
            } catch is CancellationError {
                outcome = publicationProblem.map(ExportJob.Outcome.failed) ?? .cancelled
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            if FileManager.default.fileExists(atPath: staging.path(percentEncoded: false)) {
                do { try FileManager.default.removeItem(at: staging) }
                catch { warnings.append("Couldn't remove temporary export files in \(staging.path(percentEncoded: false)): \(error.localizedDescription)") }
            }
            if let warning = releaseAudio(for: attempt.entry) { warnings.append(warning) }
            queue.finish(outcome, for: attempt, warnings: warnings)
            task = nil
            runNext()
        }
    }

    private func releaseAudio(for id: UUID) -> String? {
        guard let snapshot = resources[id]?.audio else { return nil }
        resources[id]?.audio = nil
        do { try snapshot.release(); return nil }
        catch { return "Couldn't remove this export's temporary audio: \(error.localizedDescription)" }
    }

    nonisolated private static func render(_ plan: ExportPlan, event: @escaping @Sendable (FinishedExporter.Event) async -> Void) async throws -> ExportResult {
        switch plan.kind {
        case .finished:
            let target = plan.inputs.edit.audio.loudnessTarget
            let ceiling = plan.inputs.edit.audio.truePeakCeiling
            let mastering: Exporter.Mastering = { samples, rate in
                try LoudnessStage.process(AudioSamples(samples: samples, sampleRate: rate), target: target, ceiling: ceiling,
                                          checkpoint: { try Task.checkCancellation() }).audio.samples
            }
            return try await FinishedExporter.run(plan, mastering: mastering, event: event)
        case .handoff:
            await event(.preparing(.handoff))
            let result = try await exportHandoff(plan)
            await event(.completed(.handoff, result.files))
            return result
        }
    }

    /// The helper receives the captured plan, not a project path that it would reload later.
    nonisolated private static func exportHandoff(_ plan: ExportPlan) async throws -> ExportResult {
        let snapshot = FileManager.default.temporaryDirectory.appending(path: "cuecan-export-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try plan.write(to: snapshot)
        let output = try await CommandRunner.run(executable: ProcessingCenter.cli,
                                                 arguments: ["--machine", "export_plan", snapshot.path(percentEncoded: false)])
        guard case .exported(let result) = try HelperMessage.result(in: output) else {
            throw HelperMessage.Failure("The export returned an unexpected result.")
        }
        return result
    }
}

/// A creator-facing destination shared by every take, independent of the project package's files.
enum ExportPreferences {
    static let folderKey = "LastExportFolder"
    static var defaultFolder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        return movies.appending(path: "CueCan Exports", directoryHint: .isDirectory)
    }
    static func folder(in defaults: UserDefaults = .standard) -> URL {
        guard let path = defaults.string(forKey: folderKey), !path.isEmpty else { return defaultFolder }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
    static func remember(_ folder: URL, in defaults: UserDefaults = .standard) {
        defaults.set(folder.path(percentEncoded: false), forKey: folderKey)
    }
}

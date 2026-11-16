import Foundation
import ProjectKit
import RenderKit
import Testing
@testable import CueCan

/// Controlled renderer callbacks exercise the app's real queue ownership and final-file publication.
/// Fixture bytes deliberately are not media; rendering quality is checked separately on QA exports.
@MainActor
struct ExportCenterTests {
    @Test func aLateCompletionAfterStopCannotPublishFiles() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = ExportGate()
        let center = ExportCenter(renderer: { plan, event in
            await gate.wait()
            // A helper or callback can finish after cancellation and on an uncancelled task.
            for file in plan.outputURLs { try Data("Late output".utf8).write(to: file) }
            await Task.detached { await event(.completed(.transcript, plan.outputURLs)) }.value
            return ExportResult(files: plan.outputURLs)
        })
        let plan = fixture.plan("Stopped")
        try center.enqueue(plan)
        try await waitUntil { gate.started == 1 }
        center.stop(center.entries[0].id)
        gate.release()
        try await waitUntil { center.activeCount == 0 }
        #expect(center.entries[0].job.phase == .finished(.cancelled))
        #expect(center.entries[0].job.rows.flatMap(\.files).isEmpty)
        #expect(plan.outputURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(try stagedFolders(in: fixture.destination).isEmpty)
    }

    @Test func queuedAudioSurvivesCleanupAndEachExportReleasesOnlyItsOwnLinks() async throws {
        let fixture = try Fixture(withCleanedAudio: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = ExportGate()
        let center = ExportCenter(renderer: renderer(gate))
        try center.enqueue(fixture.plan("First"))
        try center.enqueue(fixture.plan("Queued"))
        try await waitUntil { gate.started == 1 }
        let source = try #require(fixture.inputs.project.sources.first?.id)
        let original = try #require(fixture.inputs.primaryAudio[source])
        let first = try #require(center.plan(for: center.entries[0].id)?.inputs.primaryAudio[source])
        let second = try #require(center.plan(for: center.entries[1].id)?.inputs.primaryAudio[source])
        #expect(first != original && second != original && first != second)
        try FileManager.default.removeItem(at: original)
        #expect(try String(contentsOf: first, encoding: .utf8) == "First cleaned audio")
        #expect(try String(contentsOf: second, encoding: .utf8) == "First cleaned audio")
        center.stop(center.entries[1].id)
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: first.path))
        gate.release()
        try await waitUntil { center.activeCount == 0 }
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(gate.started == 1)
    }

    @Test func cancellingTheSetupTaskDoesNotCancelExportsAndTheNextExportWaits() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = ExportGate()
        let center = ExportCenter(renderer: renderer(gate))
        let first = fixture.plan("First")
        let second = fixture.plan("Second")
        let setup = Task {
            try center.enqueue(first)
            try await Task.sleep(for: .seconds(60))
        }
        try await waitUntil { gate.started == 1 }
        setup.cancel()
        _ = await setup.result
        try center.enqueue(second)
        #expect(center.activity(for: first.inputs.folder.url) != nil)
        #expect(center.entries[0].job.phase == .running)
        #expect(center.entries[1].job.phase == .setup)
        #expect(gate.started == 1)
        gate.release()
        try await waitUntil { gate.started == 2 }
        #expect(center.entries[0].job.phase == .finished(.success))
        #expect(center.entries[0].job.rows.flatMap(\.files) == first.outputURLs)
        gate.release()
        try await waitUntil { center.activeCount == 0 }
        #expect(center.entries.allSatisfy { $0.job.phase == .finished(.success) })
        #expect(center.activity(for: first.inputs.folder.url) == nil)
        #expect((first.outputURLs + second.outputURLs).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(try stagedFolders(in: fixture.destination).isEmpty)
    }

    @Test func stoppingActiveAndQueuedExportsCleansStagingWithoutStartingQueuedWork() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = ExportGate()
        let center = ExportCenter(renderer: renderer(gate))
        try center.enqueue(fixture.plan("First"))
        try center.enqueue(fixture.plan("Second"))
        try await waitUntil { gate.started == 1 }
        center.stop(center.entries[1].id)
        center.stop(center.entries[0].id)
        #expect(center.entries[0].job.phase == .stopping)
        gate.release()
        try await waitUntil { center.activeCount == 0 }
        #expect(center.entries.allSatisfy { $0.job.phase == .finished(.cancelled) })
        #expect(gate.started == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
    }

    @Test func aFileCreatedDuringRenderingIsPreservedAndTheExportReportsFailure() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = ExportGate()
        let center = ExportCenter(renderer: renderer(gate))
        let plan = fixture.plan("Collision")
        try center.enqueue(plan)
        try await waitUntil { gate.started == 1 }
        let existing = plan.fileURL(extension: "txt")
        try Data("Keep the earlier file".utf8).write(to: existing)
        gate.release()
        try await waitUntil { center.activeCount == 0 }
        guard case .finished(.failed) = center.entries[0].job.phase else { Issue.record("A publication collision must fail the export."); return }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "Keep the earlier file")
        #expect(!FileManager.default.fileExists(atPath: plan.fileURL(extension: "srt").path))
        #expect(center.entries[0].job.rows.flatMap(\.files).isEmpty)
        #expect(try stagedFolders(in: fixture.destination).isEmpty)
    }

    @Test func exportFoldersAreRememberedAcrossTakesOutsideTheProject() throws {
        let suite = "CueCanExportPreferenceTest-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ExportPreferences.folder(in: defaults).lastPathComponent == "CueCan Exports")
        let chosen = URL(filePath: "/tmp/Creator exports", directoryHint: .isDirectory)
        ExportPreferences.remember(chosen, in: defaults)
        #expect(ExportPreferences.folder(in: defaults).pathComponents == chosen.pathComponents)
    }

    private func renderer(_ gate: ExportGate) -> ExportCenter.Renderer {
        { plan, event in
            await event(.preparing(.transcript))
            await gate.wait()
            try Task.checkCancellation()
            for file in plan.outputURLs { try Data("QA output bytes".utf8).write(to: file) }
            await event(.completed(.transcript, plan.outputURLs))
            return ExportResult(files: plan.outputURLs)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while !condition() {
            guard clock.now < deadline else {
                throw NSError(domain: "ExportCenterTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for export state"])
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func stagedFolders(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".cuecan-export-") }
    }

    private struct Fixture {
        let root: URL
        let inputs: RenderInputs
        var destination: URL { root.appending(path: "exports", directoryHint: .isDirectory) }
        init(withCleanedAudio: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "cuecan-export-center-\(UUID())")
            let folder = try ProjectFolder.create(at: root.appending(path: "project"), title: "Export lifecycle fixture")
            if withCleanedAudio {
                let track = SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"),
                                        media: MediaInfo(duration: 1, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm")))
                let project = try folder.updateProject { $0.addSource(name: "Mic", origin: .recorded, tracks: [track]) }
                let source = try #require(project.sources.first?.id)
                let name = "\(source)-first.wav"
                try Data("First cleaned audio".utf8).write(to: folder.url(for: .audio).appending(path: name))
                try folder.saveCleanedAudio(.init(source: source, settings: folder.loadEdit().audio.settings(for: source),
                                                 file: name, original: track.file))
            }
            inputs = try RenderInputs.load(folder)
        }
        func plan(_ name: String) -> ExportPlan {
            ExportPlan(inputs: inputs, destination: destination,
                       kind: .finished(outputs: [], transcript: true, settings: .init()), name: name)
        }
    }
}

@MainActor
private final class ExportGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var started = 0
    func wait() async {
        started += 1
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }
}

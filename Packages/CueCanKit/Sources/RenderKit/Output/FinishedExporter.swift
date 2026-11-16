import Foundation
import ProjectKit

/// Shared app/CLI orchestration. Audio mastering remains injected to keep RenderKit independent of AudioKit.
public enum FinishedExporter {
    public enum Event: Sendable {
        case preparing(ExportJob.Item)
        case progress(ExportJob.Item, Double)
        case completed(ExportJob.Item, [URL])
    }
    public static func run(_ plan: ExportPlan, mastering: Exporter.Mastering?,
                           event: @escaping @Sendable (Event) async -> Void = { _ in }) async throws -> ExportResult {
        guard case .finished(let outputs, let transcript, let settings) = plan.kind else {
            throw RenderError.exportFailed("A finished-video export needs video settings.")
        }
        var files: [URL] = []
        for output in outputs {
            try Task.checkCancellation()
            await event(.preparing(.video(output)))
            let url = plan.videoURL(output)
            try await Exporter.export(plan.inputs, output: output, to: url, settings: settings, mastering: mastering) {
                let progress = $0
                Task { await event(.progress(.video(output), progress)) }
            }
            files.append(url)
            await event(.completed(.video(output), [url]))
        }
        try Task.checkCancellation()
        if transcript {
            await event(.preparing(.transcript))
            let written = try writeTranscripts(plan)
            files += written
            await event(.completed(.transcript, written))
        }
        return ExportResult(files: files)
    }

    /// The same captions and filenames accompany both export kinds.
    public static func writeTranscripts(_ plan: ExportPlan) throws -> [URL] {
        let srt = plan.fileURL(extension: "srt")
        let text = plan.fileURL(extension: "txt")
        try Exporter.writeSRT(plan.inputs, to: srt)
        try Exporter.writeText(plan.inputs, to: text)
        return [srt, text]
    }
}

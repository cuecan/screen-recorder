import Foundation
import MCP
import ProcessingKit
import ProjectKit
import RenderKit

/// The export for another editor (docs/decisions.md, 60): an FCPXML timeline written from the edit, with the
/// raw media referenced where it is, the mic cleaned without Voice, and the transcript as SRT and text.
struct ExportTimelineTool: EditorTool {
    let name = "export_timeline"
    let description = """
        For finishing in Final Cut Pro or DaVinci Resolve: writes an FCPXML timeline from the edit to exports/ \
        (one project per shape the format makes, each clip laid out as previewed), referencing the raw screen, \
        camera and system audio in the project folder, and the mic twice, as recorded and cleaned (Cleanup \
        only: Voice and loudness belong to the other editor's mix), with the SRT and plain-text transcript. \
        split_at_silences blades the clips at every silence without removing anything and marks the silent \
        pieces with a Silence keyword and role, so the editor can delete them all at once. Media isn't copied.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "split_at_silences": Schema.boolean("Blade at every silence and mark the silent pieces."),
                "folder": Schema.string("Where to write, instead of the project's exports folder."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let inputs = try RenderInputs.load(folder)
        let destination = try arguments.optionalString("folder").map { URL(filePath: ($0 as NSString).expandingTildeInPath, directoryHint: .isDirectory) }
            ?? folder.url(for: .exports)
        let plan = ExportPlan(inputs: inputs, destination: destination,
                              kind: .handoff(splitAtSilences: try arguments.optionalBool("split_at_silences") == true))
        let result = try await Self.export(plan)
        return ToolOutput(text: (["Wrote:"] + result.files.map { $0.path(percentEncoded: false) } + result.warnings
                                 + ["The media stays in the project folder; keep it there for the timeline to find it."]).joined(separator: "\n"), exported: result)
    }

    /// Uses the caller's snapshot for both the timeline and the cleanup settings.
    static func export(_ plan: ExportPlan) async throws -> ExportResult {
        guard case .handoff(let split) = plan.kind else { throw RenderError.exportFailed("A timeline export needs handoff settings.") }
        let inputs = plan.inputs
        let processor = SourceProcessor()
        var audio: [SourceID: FCPXMLWriter.SourceAudio] = [:]
        var notes: [String] = []
        for id in Set(inputs.edit.main.map(\.source)).sorted() {
            try Task.checkCancellation()
            guard let source = inputs.project.source(id), source.primaryAudioTrack != nil else { continue }
            do {
                let cleaned = try await processor.cleanupOnly(source, settings: inputs.edit.audio.settings(for: id), in: inputs.folder)
                audio[id] = FCPXMLWriter.SourceAudio(cleanedMic: cleaned)
            } catch is CancellationError { throw CancellationError() }
            catch {
                notes.append("Couldn't clean \(id)'s mic, so only the mic as recorded is in the timeline: \(error.localizedDescription)")
            }
        }
        try Task.checkCancellation()
        let fcpxml = plan.fileURL(extension: "fcpxml")
        let options = FCPXMLWriter.Options(outputs: inputs.project.effectiveFormat.outputs, splitAtSilences: split)
        try FCPXMLWriter.write(inputs, options: options, audio: audio, to: fcpxml)
        let transcripts = try FinishedExporter.writeTranscripts(plan)
        return ExportResult(files: [fcpxml] + transcripts, warnings: notes)
    }
}

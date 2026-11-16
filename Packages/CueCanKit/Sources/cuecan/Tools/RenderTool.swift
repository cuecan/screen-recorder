import Foundation
import MCP
import ProjectKit
import RenderKit

struct RenderTool: EditorTool {
    let name = "render"
    let description = """
        The finished video: renders the edit to exports/ in each shape the project's format makes (a 16:9 video, \
        a 9:16 Short, or both), laid out as previewed, with an SRT and a plain-text transcript timed to the \
        edit, the sound cleaned and levelled to −14 LUFS for YouTube. Nothing is burned into the picture. Check \
        with preview_frames first: rendering takes a while. For Final Cut or Resolve, use export_timeline.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "codec": Schema.oneOf(ExportSettings.Codec.allCases.map(\.rawValue), "hevc (smaller) or h264 (plays everywhere). hevc if left out."),
                "four_k": Schema.boolean("Render at 4K instead of 1080p."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let inputs = try RenderInputs.load(folder)
        let codec = try arguments.optionalString("codec").map { name in
            guard let codec = ExportSettings.Codec(rawValue: name) else { throw ToolError.invalidValue("codec", "use hevc or h264.") }
            return codec
        } ?? .hevc
        let settings = ExportSettings(codec: codec, scale: try arguments.optionalBool("four_k") == true ? 2 : 1)
        let mastering = ToolContext.mastering(target: inputs.edit.audio.loudnessTarget, ceiling: inputs.edit.audio.truePeakCeiling)

        let plan = ExportPlan(inputs: inputs, destination: folder.url(for: .exports),
                              kind: .finished(outputs: inputs.project.effectiveFormat.outputs, transcript: true, settings: settings))
        let result = try await FinishedExporter.run(plan, mastering: mastering)
        return ToolOutput(text: "Rendered:\n" + result.files.map { $0.path(percentEncoded: false) }.joined(separator: "\n"), exported: result)
    }
}

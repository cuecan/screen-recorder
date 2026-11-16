import Foundation
import MCP
import ProjectKit

struct RemoveSilencesTool: EditorTool {
    let name = "remove_silences"
    let description = """
        Shortens every pause the edit plays that's longer than longer_than seconds, leaving leave seconds of air \
        so the speech doesn't sound rushed.
        """
    var inputSchema: Value {
        Schema.object(
            [
                "project": Schema.project,
                "longer_than": Schema.number("Pauses longer than this many seconds are shortened. 0.7 if left out."),
                "leave": Schema.number("Seconds of pause to leave. 0.3 if left out."),
            ],
            required: ["project"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let threshold = try arguments.optionalDouble("longer_than") ?? Edit.defaultSilenceThreshold
        let air = try arguments.optionalDouble("leave") ?? Edit.defaultSilenceAir
        let (edit, count) = try context.change(folder, reason: "Shortened pauses over \(threshold) s to \(air) s") { edit, transcripts in
            try edit.removeSilences(longerThan: threshold, leaving: air, transcripts: transcripts)
        }
        return try EditingOutput.after("Shortened \(count) pauses.", edit: edit, folder: folder)
    }
}

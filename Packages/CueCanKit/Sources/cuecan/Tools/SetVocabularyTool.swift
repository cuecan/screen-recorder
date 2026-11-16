import Foundation
import MCP
import ProcessingKit
import ProjectKit

struct SetVocabularyTool: EditorTool {
    let name = "set_vocabulary"
    let description = """
        Gives the names and jargon the video uses, from its CueCan script or from what the creator says it's about, \
        such as product names, people and technical terms. Vocabulary boosting then checks every transcribed source \
        and swaps a term in where the audio supports it; the swaps show in get_transcript as spellings. It's strict, \
        so it misses words heard as something else entirely: catch those yourself, with SpeechAnalyzer's readings. \
        The first time, it downloads a 97.5 MB model.
        """
    var inputSchema: Value {
        Schema.object(
            ["project": Schema.project, "terms": Schema.list(of: ["type": "string"], "The terms, each as it should be spelled.")],
            required: ["project", "terms"]
        )
    }

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let terms = (try arguments.strings("terms") ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let project = try folder.updateProject { $0.vocabulary = terms }
        guard !terms.isEmpty else {
            try folder.removeAllSpellings()
            return ToolOutput(text: "Cleared the vocabulary and its spellings.")
        }

        let processor = SourceProcessor()
        var lines = ["Vocabulary: \(terms.joined(separator: ", "))."]
        for source in project.sources where source.transcriptFile != nil {
            guard let spellings = try await processor.applyVocabulary(to: source.id, in: folder) else { continue }
            let swaps = spellings.spellings.map { "\($0.words) → \($0.text)" }
            lines.append("\(source.id): " + (swaps.isEmpty ? "no swaps." : swaps.joined(separator: "; ")))
        }
        if lines.count == 1 { lines.append("No source is transcribed yet; the terms apply as each one is.") }
        return ToolOutput(text: lines.joined(separator: "\n"))
    }
}

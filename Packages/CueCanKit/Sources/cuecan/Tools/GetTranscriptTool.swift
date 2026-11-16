import Foundation
import MCP
import ProjectKit

struct GetTranscriptTool: EditorTool {
    let name = "get_transcript"
    let description = """
        The project's transcripts: every word and pause with its id and times, which of them the edit plays, \
        filler words and retakes. Cut and keep by these ids, never by quoting text or by time.
        Two engines heard the audio. Parakeet wrote the transcript and its ids: it keeps repeats, false starts \
        and fillers, which is how retakes are found. Apple's SpeechAnalyzer gave a second reading, shown where it \
        heard something different: it's often right on clean speech and names. Use it to spell; cut by Parakeet's ids.
        Vocabulary terms set with set_vocabulary show as spellings over the words they replace.
        """
    var inputSchema: Value {
        Schema.object(
            ["project": Schema.project, "source": Schema.string("Only this source, such as src_1. Leave out for all.")],
            required: ["project"]
        )
    }
    let readOnly = true

    func run(_ arguments: ToolArguments, context: ToolContext) async throws -> ToolOutput {
        let folder = try context.folder(arguments)
        let only = try arguments.optionalSourceID("source")
        let project = try folder.loadProject()
        let edit = try folder.loadEdit()
        let transcripts = try folder.loadTranscripts(fixedBy: edit)
        var sections = [TranscriptText.legend]
        for source in project.sources where only == nil || source.id == only {
            guard let transcript = transcripts[source.id] else {
                sections.append("\(source.id) · \(source.name) · not transcribed yet")
                continue
            }
            sections.append(
                TranscriptText.text(transcript, source: source, used: edit.usedItems(of: transcript), spellings: try folder.currentSpellings(for: source.id, terms: project.vocabulary))
            )
        }
        if let only, project.source(only) == nil { throw EditError.unknownSource(only) }
        return ToolOutput(text: sections.joined(separator: "\n\n"))
    }
}

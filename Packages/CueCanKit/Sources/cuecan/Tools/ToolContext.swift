import AudioKit
import Foundation
import ProjectKit
import RenderKit

/// What every tool shares: where projects are, who's editing, and how exports are mastered.
struct ToolContext: Sendable {
    var library: ProjectLibrary
    /// Written into each history snapshot, so the app can show Claude's changes.
    var author: EditAuthor

    init(library: ProjectLibrary = ProjectLibrary(), author: EditAuthor = .agent("Claude")) {
        self.library = library
        self.author = author
    }

    func folder(_ arguments: ToolArguments) throws -> ProjectFolder {
        let folder = try library.find(try arguments.string("project"))
        library.noteOpened(folder)
        return folder
    }

    /// Makes one change to the edit under the project's lock, with its transcripts, and snapshots it.
    func change<Result>(
        _ folder: ProjectFolder,
        reason: String,
        _ body: (inout Edit, TranscriptIndex) throws -> Result
    ) throws -> (edit: Edit, result: Result) {
        var result: Result?
        let edit = try folder.updateEdit(author: author, reason: reason) { edit, transcripts in
            result = try body(&edit, transcripts)
        }
        guard let result else { throw ToolError.invalidValue("edit", "the change didn't run.") }
        return (edit, result)
    }

    /// AudioKit's Loudness stage on the final mix, to the edit's target and ceiling.
    static func mastering(target: Double, ceiling: Double) -> Exporter.Mastering {
        { samples, sampleRate in
            try LoudnessStage.process(AudioSamples(samples: samples, sampleRate: sampleRate), target: target, ceiling: ceiling,
                                      checkpoint: { try Task.checkCancellation() }).audio.samples
        }
    }
}

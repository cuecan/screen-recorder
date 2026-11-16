import Foundation
import ProjectKit

/// Immutable project inputs, including resolved primary audio, captured under the folder lock.
/// A later processing pass cannot change which audio an in-flight preview or export uses.
public struct RenderInputs: Sendable, Codable {
    public let folder: ProjectFolder
    public let project: Project
    public let edit: Edit
    public let transcripts: TranscriptIndex
    public let spellings: [SourceID: VocabularySpellings]
    public let primaryAudio: [SourceID: URL]
    /// Each source's measured levels, where they've been measured, for captions that start words on their
    /// sound (docs/decisions.md, 80).
    public let levels: [SourceID: SourceLevels]

    init(folder: ProjectFolder, project: Project, edit: Edit, transcripts: TranscriptIndex,
                spellings: [SourceID: VocabularySpellings], primaryAudio: [SourceID: URL], levels: [SourceID: SourceLevels] = [:]) {
        self.folder = folder
        self.project = project
        self.edit = edit
        self.transcripts = transcripts
        self.spellings = spellings
        self.primaryAudio = primaryAudio
        self.levels = levels
    }

    /// Reads everything a render needs. Each mic plays its voice cleaned with its current settings, or the raw
    /// recording until that's made. With `keepingEarlierCleaning`, as the editor's preview loads, a mic being
    /// cleaned again keeps its last cleaned voice instead, so the sound doesn't drop to the raw recording and
    /// back (docs/decisions.md, 71).
    public static func load(_ folder: ProjectFolder, keepingEarlierCleaning: Bool = false) throws -> RenderInputs {
        try folder.withLock {
            let project = try folder.loadProject()
            let edit = try folder.loadEdit()
            var spellings: [SourceID: VocabularySpellings] = [:]
            var audio: [SourceID: URL] = [:]
            var levels: [SourceID: SourceLevels] = [:]
            for source in project.sources {
                spellings[source.id] = try folder.currentSpellings(for: source.id, terms: project.vocabulary)
                if let track = source.primaryAudioTrack {
                    levels[source.id] = folder.loadLevels(for: source.id, original: track.file)
                    audio[source.id] = folder.cleanedAudioURL(for: source.id, settings: edit.audio.settings(for: source.id), original: track.file)
                        ?? (keepingEarlierCleaning ? folder.latestCleanedAudioURL(for: source.id, original: track.file) : nil)
                        ?? track.file.url(relativeTo: folder.url)
                }
            }
            return RenderInputs(folder: folder, project: project, edit: edit, transcripts: try folder.loadTranscripts(fixedBy: edit),
                                spellings: spellings, primaryAudio: audio, levels: levels)
        }
    }

    /// The same inputs with the edit changed in memory, for previewing a change without saving it, as
    /// `preview_frames` does with a layout.
    public func withEdit(_ change: (inout Edit) throws -> Void) rethrows -> RenderInputs {
        var edit = edit
        try change(&edit)
        return RenderInputs(folder: folder, project: project, edit: edit, transcripts: transcripts, spellings: spellings, primaryAudio: primaryAudio, levels: levels)
    }

    /// Whether these inputs make the same composition as `other`, tracks and pictures alike, and differ at
    /// most in the mix: clips' and overlays' levels, and Cleanup and Voice settings while each mic plays the
    /// same file. Then a playing preview can take the new mix without being rebuilt.
    public func differsOnlyInMix(from other: RenderInputs) -> Bool {
        func withoutMix(_ edit: Edit) -> Edit {
            var edit = edit
            edit.revision = 0
            edit.audio = AudioSettings()
            for index in edit.main.indices {
                edit.main[index].voiceLevel = 0
                edit.main[index].systemAudioLevel = 0
            }
            for index in edit.overlays.indices { edit.overlays[index].level = 0 }
            return edit
        }
        return folder.url == other.folder.url && project == other.project && primaryAudio == other.primaryAudio
            && levels == other.levels && spellings == other.spellings && transcripts.transcripts == other.transcripts.transcripts
            && withoutMix(edit) == withoutMix(other.edit)
    }

    /// Static framing changes crops, not media or timing. A playing item can take new drawing instructions
    /// in place, including while a slider is being auditioned without saving an edit.
    public func differsOnlyInFraming(from other: RenderInputs) -> Bool {
        func withoutFraming(_ edit: Edit) -> Edit {
            var edit = edit
            edit.revision = 0
            edit.camera = [:]
            for index in edit.main.indices {
                edit.main[index].screenTransform = nil
                edit.main[index].cameraTransform = nil
            }
            return edit
        }
        return folder.url == other.folder.url && project == other.project && primaryAudio == other.primaryAudio
            && levels == other.levels && spellings == other.spellings && transcripts.transcripts == other.transcripts.transcripts
            && withoutFraming(edit) == withoutFraming(other.edit)
    }

    public func srtCues(timeline: EditTimeline) -> [CaptionCue] {
        CaptionBuilder.cues(edit: edit, timeline: timeline, transcripts: transcripts, spellings: spellings)
    }

    private enum CodingKeys: String, CodingKey { case folder, project, edit, transcripts, spellings, primaryAudio, levels }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        folder = try ProjectFolder(opening: values.decode(URL.self, forKey: .folder))
        project = try values.decode(Project.self, forKey: .project)
        edit = try values.decode(Edit.self, forKey: .edit)
        transcripts = TranscriptIndex(try values.decode([Transcript].self, forKey: .transcripts))
        spellings = try values.decode([SourceID: VocabularySpellings].self, forKey: .spellings)
        primaryAudio = try values.decode([SourceID: URL].self, forKey: .primaryAudio)
        levels = try values.decode([SourceID: SourceLevels].self, forKey: .levels)
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(folder.url, forKey: .folder)
        try values.encode(project, forKey: .project)
        try values.encode(edit, forKey: .edit)
        try values.encode(transcripts.transcripts.values.sorted { $0.source < $1.source }, forKey: .transcripts)
        try values.encode(spellings, forKey: .spellings)
        try values.encode(primaryAudio, forKey: .primaryAudio)
        try values.encode(levels, forKey: .levels)
    }
}

import Foundation

/// A project as the projects window and `list_projects` show it: its sources and how far each has got.
public struct ProjectSummary: Codable, Equatable, Sendable, Identifiable {
    /// One source's progress.
    public struct SourceStatus: Codable, Equatable, Sendable {
        public var id: SourceID
        public var name: String
        public var origin: Source.Origin
        /// It has a screen track: false for a recording of the camera alone (docs/ui.md, R9) and for footage.
        public var hasScreen: Bool
        public var duration: TimeInterval
        /// Lined up with the rest of the project: recorded on the host clock, synced, or its own reference.
        public var synced: Bool
        public var transcribed: Bool
        /// Its mic has a cleaned voice for the current settings. Nil when it has no audio to clean.
        public var cleaned: Bool?
    }

    public var id: UUID
    public var url: URL
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var format: VideoFormat
    /// The shape the editor last showed, which the sidebar's thumbnail shows too: for a take made for both,
    /// the 16:9 video until the toggle is flipped to the 9:16 Short (docs/decisions.md, 77).
    public var shape: OutputShape
    /// The project this one was duplicated from, for a copy.
    public var copyOf: UUID?
    public var sources: [SourceStatus]
    /// The edit's length in seconds, and how many changes it has had.
    public var editDuration: TimeInterval
    public var editRevision: Int

    /// Reads a project folder's summary.
    public init(folder: ProjectFolder) throws(ProjectFolderError) {
        let project = try folder.loadProject()
        let edit = try folder.loadEdit()
        id = project.id
        url = folder.url
        title = project.title
        createdAt = project.createdAt
        let modified = try? folder.editFileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        modifiedAt = modified ?? project.createdAt
        format = project.effectiveFormat
        let outputs = project.effectiveFormat.outputs
        shape = (try? folder.loadEditorState())?.shape.flatMap { outputs.contains($0) ? $0 : nil } ?? outputs[0]
        copyOf = project.copyOf
        editDuration = edit.duration
        editRevision = edit.revision
        sources = project.sources.map { source in
            let cleaned = source.primaryAudioTrack.map { track in
                folder.cleanedAudioURL(for: source.id, settings: edit.audio.settings(for: source.id), original: track.file) != nil
            }
            return SourceStatus(
                id: source.id,
                name: source.name,
                origin: source.origin,
                hasScreen: source.track(.screen) != nil,
                duration: source.duration,
                synced: source.origin == .recorded || source.sync != nil || project.sources.first?.id == source.id,
                transcribed: source.transcriptFile != nil,
                cleaned: cleaned
            )
        }
    }
}

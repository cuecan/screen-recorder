import Foundation
import ProjectKit

/// Deletes a discarded take's project, outright, with no Trash to recover it from (docs/decisions.md, 51).
///
/// A recording creates its project folder when it starts, and only adds its source to the project on
/// Stop. So a discarded take's project has no sources, and that's checked before anything is deleted:
/// a project that holds anything else is never removed.
public enum DiscardedTake {
    public enum Refusal: Error, Equatable, LocalizedError {
        /// The folder isn't directly inside the projects folder.
        case notInProjectsFolder(URL)
        /// The project already holds sources, so it isn't only this take.
        case projectHasSources(URL)

        public var errorDescription: String? {
            switch self {
            case .notInProjectsFolder(let url):
                "The take wasn't deleted, because its project “\(url.lastPathComponent)” isn't in CueCan's projects folder."
            case .projectHasSources(let url):
                "The take wasn't deleted, because its project “\(url.lastPathComponent)” already has other recordings in it."
            }
        }
    }

    /// Deletes the project folder a discarded take created. Stop the session's writers first, with
    /// ``RecordingSession/discard()``.
    ///
    /// - Parameter projectsFolder: The library's projects folder; the project must sit directly inside it.
    public static func delete(_ folder: ProjectFolder, in projectsFolder: URL) throws {
        let parent = folder.url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        guard parent.path(percentEncoded: false) == projectsFolder.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        else { throw Refusal.notInProjectsFolder(folder.url) }
        guard try folder.loadProject().sources.isEmpty else { throw Refusal.projectHasSources(folder.url) }
        try FileManager.default.removeItem(at: folder.url)
    }
}

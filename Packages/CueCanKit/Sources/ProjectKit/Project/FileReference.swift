import Foundation

/// Where a track's file is: inside the project folder, or anywhere else on disk.
///
/// Recorded files are stored relative to the project folder, so the folder can be moved. Imported files
/// stay where they are and are stored as absolute paths. They're never copied or modified.
public struct FileReference: Codable, Hashable, Sendable {
    /// A path relative to the project folder (no leading slash), or an absolute path.
    public var path: String

    public init(path: String) {
        self.path = path
    }

    /// A file inside the project folder, such as `recordings/mic.wav`.
    public static func inProject(_ relativePath: String) -> FileReference {
        FileReference(path: relativePath)
    }

    /// A file elsewhere on disk, referenced where it is.
    public static func external(_ url: URL) -> FileReference {
        FileReference(path: url.standardizedFileURL.path(percentEncoded: false))
    }

    /// Whether the file is outside the project folder.
    public var isExternal: Bool { path.hasPrefix("/") }

    /// The file's location, given the project folder it belongs to.
    public func url(relativeTo projectFolder: URL) -> URL {
        isExternal ? URL(filePath: path) : projectFolder.appending(path: path)
    }
}

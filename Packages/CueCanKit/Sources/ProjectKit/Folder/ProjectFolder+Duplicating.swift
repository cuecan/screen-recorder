import Foundation

/// Duplicating a project (docs/decisions.md, 77): a copy with its own edit, for a Short that should be cut or
/// look different from its video. No edit changes the recordings, so the copy needs none of its own: its
/// folder is a copy of the original's, which on an APFS volume shares the recordings' data until one side
/// changes, and they never do. Each project stays a plain folder that can be moved or put in the Trash alone.
extension ProjectFolder {
    /// What a copy starts without: the original's lock and unfinished change, and its exports, which were made
    /// from the original's edit.
    static let notDuplicated: Set<String> = [lockFileName, pendingMutationFileName, Folder.exports.rawValue]

    /// Copies the project into a new folder at `destination`, which must not exist yet, as a project of its
    /// own: a new id, `title`, and the original's id in ``Project/copyOf``. The edit, its history, the
    /// transcripts and where the editor was all come along. Held under the original's lock, so no change is
    /// caught half-saved.
    public func duplicate(to destination: URL, title: String) throws(ProjectFolderError) -> ProjectFolder {
        let copy = ProjectFolder(unchecked: destination)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: copy.url.path(percentEncoded: false)) else { throw .alreadyAProject(copy.url) }
        do {
            try withLock {
                let original = try loadProject()
                try fileManager.createDirectory(at: copy.url, withIntermediateDirectories: true)
                // project.json last: it's the marker that a project is whole.
                let names = try fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false))
                for name in names where !Self.notDuplicated.contains(name) && name != Self.projectFileName {
                    try fileManager.copyItem(at: url.appending(path: name), to: copy.url.appending(path: name))
                }
                for subfolder in Folder.allCases {
                    try fileManager.createDirectory(at: copy.url(for: subfolder), withIntermediateDirectories: true)
                }
                var project = original
                project.id = UUID()
                project.title = title
                project.copyOf = original.id
                try copy.write(project, to: copy.projectFileURL)
            }
        } catch {
            try? fileManager.removeItem(at: copy.url)
            if let error = error as? ProjectFolderError { throw error }
            throw .couldNotWrite(copy.url, error.localizedDescription)
        }
        return copy
    }
}

extension ProjectLibrary {
    /// Duplicates a project beside itself, as "[name] copy", then "[name] copy 2" and so on, in its folder's
    /// name and its title alike.
    public func duplicate(_ folder: ProjectFolder) throws(ProjectFolderError) -> ProjectFolder {
        let parent = folder.url.deletingLastPathComponent()
        let name = Self.copyName(of: folder.url.lastPathComponent) { candidate in
            FileManager.default.fileExists(atPath: parent.appending(path: candidate).path(percentEncoded: false))
        }
        let suffix = String(name.dropFirst(Self.baseName(of: folder.url.lastPathComponent).count))
        let title = Self.baseName(of: try folder.loadProject().title) + suffix
        return try folder.duplicate(to: parent.appending(path: name, directoryHint: .isDirectory), title: title)
    }

    /// A name without a trailing " copy" or " copy 2", so a copy of a copy is named after the original.
    static func baseName(of name: String) -> String {
        guard let range = name.range(of: #" copy( \d+)?$"#, options: .regularExpression) else { return name }
        return String(name[..<range.lowerBound])
    }

    /// The first of "[name] copy", "[name] copy 2", "[name] copy 3"… that isn't taken.
    static func copyName(of name: String, isTaken: (String) -> Bool) -> String {
        let base = baseName(of: name)
        var candidate = "\(base) copy", number = 2
        while isTaken(candidate) {
            candidate = "\(base) copy \(number)"
            number += 1
        }
        return candidate
    }
}

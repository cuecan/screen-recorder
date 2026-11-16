import Foundation

/// Where projects are and which were opened lately, shared by the app and the `cuecan` CLI.
///
/// New recordings go in the projects folder, `~/Movies/CueCan` by default. Projects opened from elsewhere
/// are remembered in a short list in Application Support, so `list_projects` finds them too.
public struct ProjectLibrary: Sendable {
    /// The folder new projects are made in.
    public var projectsFolder: URL
    /// The list of recently opened projects.
    public var recentsFile: URL
    /// How many recent projects are remembered.
    public static let recentLimit = 50

    public init(projectsFolder: URL = Self.defaultProjectsFolder, recentsFile: URL = Self.defaultRecentsFile) {
        self.projectsFolder = projectsFolder
        self.recentsFile = recentsFile
    }

    public static var defaultProjectsFolder: URL {
        URL.moviesDirectory.appending(path: "CueCan", directoryHint: .isDirectory)
    }

    public static var defaultRecentsFile: URL {
        URL.applicationSupportDirectory.appending(path: "CueCan/recent-projects.json")
    }

    /// Every project in the projects folder or the recent list that still opens, newest change first.
    /// Folders that can't be read are left out rather than failing the whole list.
    public func projects() -> [ProjectSummary] {
        var seen = Set<String>()
        var summaries: [ProjectSummary] = []
        for url in candidateURLs() {
            guard let folder = try? ProjectFolder(opening: url), seen.insert(folder.url.path(percentEncoded: false)).inserted,
                let summary = try? ProjectSummary(folder: folder)
            else { continue }
            summaries.append(summary)
        }
        return summaries.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// The look of the most recently changed project, which a new take starts with (docs/decisions.md, 66
    /// and 68): what its edit shares, with the camera side most of it plays. Nil when
    /// there's no project yet.
    public func lastLook() -> OutputLook? {
        for summary in projects() {
            if let look = (try? ProjectFolder(opening: summary.url).loadEdit())?.prevailingLook { return look }
        }
        return nil
    }

    /// Finds a project by its folder path, or by its id or title among the listed projects.
    public func find(_ reference: String) throws(ProjectFolderError) -> ProjectFolder {
        let expanded = (reference as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return try ProjectFolder(opening: URL(filePath: expanded, directoryHint: .isDirectory))
        }
        let matches = projects().filter { $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame || $0.title == reference }
        guard let match = matches.first else { throw .notAProject(URL(filePath: reference)) }
        return try ProjectFolder(opening: match.url)
    }

    /// Remembers that a project was opened, so it's listed even outside the projects folder.
    public func noteOpened(_ folder: ProjectFolder) {
        var recents = recentURLs().filter { $0.standardizedFileURL != folder.url.standardizedFileURL }
        recents.insert(folder.url, at: 0)
        let paths = recents.prefix(Self.recentLimit).map { $0.path(percentEncoded: false) }
        do {
            try FileManager.default.createDirectory(at: recentsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(paths).write(to: recentsFile, options: .atomic)
        } catch {
            // The list is a convenience: a project that isn't remembered still opens from its folder.
        }
    }

    /// A folder for a new project, named by the creator's local date and title, that doesn't exist yet.
    public func newProjectURL(title: String, date: Date = .now, timeZone: TimeZone = .current) -> URL {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        let safeTitle = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let base = "\(day) \(safeTitle)"
        var candidate = projectsFolder.appending(path: base, directoryHint: .isDirectory)
        var copy = 1
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            copy += 1
            candidate = projectsFolder.appending(path: "\(base) \(copy)", directoryHint: .isDirectory)
        }
        return candidate
    }

    private func recentURLs() -> [URL] {
        guard let data = try? Data(contentsOf: recentsFile), let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    private func candidateURLs() -> [URL] {
        let inFolder = (try? FileManager.default.contentsOfDirectory(
            at: projectsFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return recentURLs() + inFolder.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}

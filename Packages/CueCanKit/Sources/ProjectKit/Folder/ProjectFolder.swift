import Foundation

/// A project on disk: a plain folder holding `project.json`, `edit.json` and the folders around them.
///
/// ```
/// 2026-11-06 Editing with Claude/
///   project.json   the sources
///   recordings/    what the app recorded
///   proxies/       small copies for preview, regenerable
///   audio/         cleaned voice per mic source, regenerable
///   transcripts/   one per source: words and silences with ids and times
///   edit.json      the edit: a timeline of clips
///   history/       a snapshot of edit.json before every change
///   exports/
/// ```
///
/// The app and the `cuecan` CLI can both have a project open at once. Every write takes a lock on the
/// folder (`.lock`, an advisory `flock`), reads the current files, changes them and writes them back
/// atomically, so neither process overwrites the other's change.
public struct ProjectFolder: Sendable, Hashable {
    public static let projectFileName = "project.json"
    public static let editFileName = "edit.json"
    public static let lockFileName = ".lock"

    /// The folders inside a project.
    public enum Folder: String, CaseIterable, Sendable {
        case recordings, proxies, audio, transcripts, history, exports, screen
    }

    public let url: URL

    /// Opens an existing project folder, checking that it holds a `project.json` this version can read.
    ///
    /// If a change was interrupted, it's finished first, under the lock. Otherwise opening only reads, so a
    /// project in a folder CueCan can't write to, such as on a read-only disk, still opens.
    public init(opening url: URL) throws(ProjectFolderError) {
        self.url = Self.normalized(url)
        guard FileManager.default.fileExists(atPath: projectFileURL.path(percentEncoded: false)) else {
            throw .notAProject(self.url)
        }
        _ = try loadProject()
        if FileManager.default.fileExists(atPath: pendingMutationURL.path(percentEncoded: false)) {
            do {
                try withLock {}
            } catch let error as ProjectFolderError {
                throw error
            } catch {
                throw .couldNotWrite(self.url, error.localizedDescription)
            }
        }
        _ = try loadProject()
    }

    init(unchecked url: URL) {
        self.url = Self.normalized(url)
    }

    /// The same URL for a folder whether or not it exists yet: standardized, always a directory.
    private static func normalized(_ url: URL) -> URL {
        URL(filePath: url.standardizedFileURL.path(percentEncoded: false), directoryHint: .isDirectory)
    }

    /// Makes a new, empty project in `url`, creating the folder if it doesn't exist.
    public static func create(at url: URL, title: String) throws(ProjectFolderError) -> ProjectFolder {
        let folder = ProjectFolder(unchecked: url)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: folder.url, withIntermediateDirectories: true)
            try folder.withLock {
                guard !fileManager.fileExists(atPath: folder.projectFileURL.path(percentEncoded: false)) else {
                    throw ProjectFolderError.alreadyAProject(folder.url)
                }
                for subfolder in Folder.allCases {
                    try fileManager.createDirectory(at: folder.url(for: subfolder), withIntermediateDirectories: true)
                }
                try folder.write(Edit(), to: folder.editFileURL)
                // project.json is the marker that creation finished.
                try folder.write(Project(title: title), to: folder.projectFileURL)
            }
        } catch let error as ProjectFolderError {
            throw error
        } catch {
            throw .couldNotWrite(folder.url, error.localizedDescription)
        }
        return folder
    }

    // MARK: - Locations

    public var projectFileURL: URL { url.appending(path: Self.projectFileName) }
    public var editFileURL: URL { url.appending(path: Self.editFileName) }

    public func url(for folder: Folder) -> URL {
        url.appending(path: folder.rawValue, directoryHint: .isDirectory)
    }

    /// Where a source's transcript is stored.
    public func transcriptURL(for source: SourceID) -> URL {
        url(for: .transcripts).appending(path: "\(source).json")
    }

    // MARK: - Reading

    public func loadProject() throws(ProjectFolderError) -> Project {
        // The version first, so an older project says it's an older format rather than naming a missing key.
        let stamp: FormatStamp = try read(projectFileURL)
        guard stamp.formatVersion <= Project.currentFormatVersion else {
            throw .newerFormat(projectFileURL, stamp.formatVersion)
        }
        guard stamp.formatVersion == Project.currentFormatVersion else {
            throw .olderFormat(projectFileURL, stamp.formatVersion)
        }
        return try read(projectFileURL)
    }

    /// Just a file's format version.
    private struct FormatStamp: Decodable { let formatVersion: Int }

    public func loadEdit() throws(ProjectFolderError) -> Edit {
        // The version first, as for the project: an older edit says so rather than naming a missing key.
        let stamp: FormatStamp = try read(editFileURL)
        guard stamp.formatVersion <= Edit.currentFormatVersion else {
            throw .newerFormat(editFileURL, stamp.formatVersion)
        }
        guard stamp.formatVersion == Edit.currentFormatVersion else {
            throw .olderFormat(editFileURL, stamp.formatVersion)
        }
        return try read(editFileURL)
    }

    /// A source's transcript, or nil if it isn't transcribed yet.
    public func loadTranscript(for source: SourceID) throws(ProjectFolderError) -> Transcript? {
        let fileURL = transcriptURL(for: source)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let transcript: Transcript = try read(fileURL)
        guard transcript.formatVersion <= Transcript.currentFormatVersion else {
            throw .newerFormat(fileURL, transcript.formatVersion)
        }
        return transcript
    }

    /// Every transcript in the project, with the edit's fixes laid over them (docs/decisions.md, 69): the
    /// transcript everything edits and reads by id.
    public func loadTranscripts() throws(ProjectFolderError) -> TranscriptIndex {
        try loadTranscripts(fixedBy: loadEdit())
    }

    /// Every transcript in the project, with this edit's fixes laid over them.
    public func loadTranscripts(fixedBy edit: Edit) throws(ProjectFolderError) -> TranscriptIndex {
        var transcripts: [Transcript] = []
        for source in try loadProject().sources {
            if let transcript = try loadTranscript(for: source.id) {
                transcripts.append(transcript)
            }
        }
        return TranscriptIndex(transcripts, fixes: edit.fixes)
    }

    // MARK: - Writing

    /// Changes `project.json` under the folder's lock. Project changes aren't snapshotted: only the edit
    /// has history.
    @discardableResult
    public func updateProject(
        _ change: (inout Project) throws -> Void
    ) throws -> Project {
        try withLock {
            var project = try loadProject()
            try change(&project)
            try write(project, to: projectFileURL)
            return project
        }
    }

    /// Changes `edit.json` under the folder's lock, snapshotting the current version into `history/` first.
    ///
    /// Nothing is written, and no snapshot is made, if the change leaves the edit as it was.
    ///
    /// - Parameters:
    ///   - author: Who made the change, such as `claude` or `app`.
    ///   - reason: A line saying what the change was, shown in the app's list of Claude's changes.
    @discardableResult
    public func updateEdit(
        author: EditAuthor,
        reason: String,
        _ change: (inout Edit) throws -> Void
    ) throws -> Edit {
        try withLock {
            let current = try loadEdit()
            var edit = current
            try change(&edit)
            guard edit != current else { return current }
            return try saveEdit(edit, replacing: current, author: author, reason: reason, redo: [])
        }
    }

    /// Changes an edit using the transcripts with that same edit's corrections. Both are read under
    /// the mutation lock, so a concurrent correction cannot leave an operation using retired word ids.
    @discardableResult
    public func updateEdit(author: EditAuthor, reason: String,
                           _ change: (inout Edit, TranscriptIndex) throws -> Void) throws -> Edit {
        try updateEdit(author: author, reason: reason) { edit in
            let transcripts = try loadTranscripts(fixedBy: edit)
            try change(&edit, transcripts)
        }
    }

    /// Saves an edit and its redo stack together. The caller holds the project lock.
    func saveEdit(_ value: Edit, replacing current: Edit, author: EditAuthor, reason: String, redo: [RedoStack.Entry]) throws -> Edit {
        var edit = value
        edit.revision = current.revision + 1
        _ = try ProjectJSON.encoder.encode(edit)
        let snapshot = try history.prepare(snapshotOf: current, author: author, reason: reason)
        try commit(.history(edit: edit, action: .append(snapshot), redo: redo))
        return edit
    }

    /// Replaces a run of words with a fix (docs/decisions.md, 69), taking the new words' ids from
    /// `project.json`, so an id is never reused, even after an undo.
    ///
    /// - Parameter timings: The text aligned against the audio, or nil to keep the fix as one untimed word.
    @discardableResult
    public func fixWords(
        _ range: ItemRange,
        as text: String,
        timings: [AlignedWord]?,
        author: EditAuthor,
        reason: String
    ) throws -> (edit: Edit, fix: WordFix) {
        try withLock {
            var project = try loadProject()
            let current = try loadEdit()
            let transcripts = try loadTranscripts(fixedBy: current)
            var edit = current
            var next = max(project.nextWordNumber, 1)
            let fix = try edit.fixWords(range, as: text, timings: timings, transcripts: transcripts, nextWordNumber: &next)
            project.nextWordNumber = next
            try write(project, to: projectFileURL)
            return (try saveEdit(edit, replacing: current, author: author, reason: reason, redo: []), fix)
        }
    }

    /// Gives a transcript draft its project-wide ids and saves it as the source's transcript.
    ///
    /// Transcripts never change once written, so a source that already has one keeps it: transcribing
    /// again means a new source.
    @discardableResult
    public func addTranscript(_ draft: TranscriptDraft, for sourceID: SourceID) throws -> Transcript {
        try withLock {
            var project = try loadProject()
            guard let index = project.sources.firstIndex(where: { $0.id == sourceID }) else {
                throw EditError.unknownSource(sourceID)
            }
            if project.sources[index].transcriptFile != nil || FileManager.default.fileExists(atPath: transcriptURL(for: sourceID).path(percentEncoded: false)) {
                throw ProjectFolderError.alreadyTranscribed(sourceID)
            }
            let (transcript, nextWord, nextSilence) = draft.assigningIDs(
                source: sourceID,
                firstWordNumber: project.nextWordNumber,
                firstSilenceNumber: project.nextSilenceNumber
            )
            let fileURL = transcriptURL(for: sourceID)
            project.nextWordNumber = nextWord
            project.nextSilenceNumber = nextSilence
            project.sources[index].transcriptFile = fileURL.lastPathComponent
            try commit(.transcript(project: project, transcript: transcript))
            // Return what's on disk, which is what every later read will see.
            let stored: Transcript = try read(fileURL)
            return stored
        }
    }

    // MARK: - History

    /// The snapshots in `history/`, for listing changes and undoing them.
    public var history: EditHistory { EditHistory(folder: url(for: .history)) }

    /// Undoes the latest change: puts back the edit as it was before it.
    @discardableResult
    public func undo() throws -> Edit {
        try withLock {
            guard let latest = try history.latestSequence() else { throw ProjectFolderError.nothingToUndo }
            return try restore(before: latest)
        }
    }

    /// Undoes a change and every change after it: puts back the edit as it was before that change.
    @discardableResult
    public func undo(through sequence: Int) throws -> Edit {
        try withLock { try restore(before: sequence) }
    }

    /// Restores the snapshot taken before change `sequence`, and moves that snapshot and every later one
    /// into `history/undone/`, so nothing is ever deleted. Call with the lock held.
    private func restore(before sequence: Int) throws -> Edit {
        let current = try loadEdit()
        let snapshot = try history.entry(sequence)
        let undone = try history.entries(from: sequence)
        var restored = snapshot.edit
        // The revision always moves forward, so anything watching edit.json sees the undo as a change.
        restored.revision = current.revision + 1
        // Clip numbers keep counting, so an id from before the undo never names a different clip after it.
        restored.nextClipNumber = max(restored.nextClipNumber, current.nextClipNumber)
        let redo = try redoStack.entriesForUndo() + [RedoStack.Entry(edit: current, reason: undone.map(\.reason).joined(separator: "; "), author: undone.last?.author ?? .system("CueCan"))]
        try commit(.history(edit: restored, action: .undo(through: sequence), redo: redo))
        return restored
    }

    // MARK: - Files

    /// Runs `body` while holding an exclusive advisory lock on the project folder. The lock is shared with
    /// every other process that opens the same project, such as the app and the `cuecan` CLI.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        let lockPath = url.appending(path: Self.lockFileName).path(percentEncoded: false)
        let descriptor = open(lockPath, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw ProjectFolderError.couldNotLock(url, String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw ProjectFolderError.couldNotLock(url, String(cString: strerror(errno)))
        }
        defer { flock(descriptor, LOCK_UN) }
        do {
            try finishPendingMutation()
        } catch {
            throw ProjectFolderError.unfinishedChange(url, error.localizedDescription)
        }
        return try body()
    }

    static let pendingMutationFileName = ".pending-mutation.json"
    private var pendingMutationURL: URL { url.appending(path: Self.pendingMutationFileName) }

    /// Saves a change that spans several files: first what the change is, in `.pending-mutation.json`,
    /// then each file, then removes the record. Call only under the folder lock. If a write fails, the
    /// record stays, and whoever opens the project or takes the lock next finishes the change first.
    private func commit(_ mutation: ProjectMutation) throws {
        try write(mutation, to: pendingMutationURL)
        try finishPendingMutation()
    }

    private func finishPendingMutation() throws {
        guard FileManager.default.fileExists(atPath: pendingMutationURL.path(percentEncoded: false)) else { return }
        let mutation: ProjectMutation = try read(pendingMutationURL)
        switch mutation {
        case .history(let edit, let action, let redo):
            switch action {
            case .append(let snapshot): try history.save(snapshot)
            case .undo(let sequence): try history.moveToUndone(from: sequence)
            }
            try write(edit, to: editFileURL)
            try redoStack.save(redo)
        case .transcript(let project, let transcript):
            let file = transcriptURL(for: transcript.source)
            if let stored = try loadTranscript(for: transcript.source) {
                guard stored == transcript else {
                    throw ProjectFolderError.alreadyTranscribed(transcript.source)
                }
            } else {
                try write(transcript, to: file)
            }
            try write(project, to: projectFileURL)
        }
        try FileManager.default.removeItem(at: pendingMutationURL)
    }

    func read<T: Decodable>(_ fileURL: URL) throws(ProjectFolderError) -> T {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw .couldNotRead(fileURL, error.localizedDescription)
        }
        do {
            return try ProjectJSON.decoder.decode(T.self, from: data)
        } catch {
            throw .unreadable(fileURL, String(describing: error))
        }
    }

    func write<T: Encodable>(_ value: T, to fileURL: URL) throws(ProjectFolderError) {
        do {
            let data = try ProjectJSON.encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .couldNotWrite(fileURL, error.localizedDescription)
        }
    }
}

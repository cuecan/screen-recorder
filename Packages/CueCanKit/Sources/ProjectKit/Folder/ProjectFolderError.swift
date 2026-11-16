import Foundation

/// Why a project folder couldn't be opened, read or written. The messages can reach the app's UI and
/// Claude, so they say what's wrong in plain words.
public enum ProjectFolderError: Error, Equatable, Sendable, LocalizedError {
    case notAProject(URL)
    case alreadyAProject(URL)
    case newerFormat(URL, Int)
    case olderFormat(URL, Int)
    case couldNotRead(URL, String)
    case unreadable(URL, String)
    case couldNotWrite(URL, String)
    case couldNotLock(URL, String)
    /// A change spanning several files was interrupted, and finishing it failed. Some files may already
    /// contain the change. Keep the recovery journal so the remaining writes can be completed.
    case unfinishedChange(URL, String)
    case alreadyTranscribed(SourceID)
    case nothingToUndo
    case nothingToRedo
    case unknownHistoryEntry(Int)

    public var errorDescription: String? {
        switch self {
        case .notAProject(let url):
            "“\(url.lastPathComponent)” isn't a CueCan project: it has no project.json."
        case .alreadyAProject(let url):
            "“\(url.lastPathComponent)” is already a CueCan project."
        case .olderFormat(let url, let version):
            "\(url.lastPathComponent) uses an older development format (\(version)). Create a new recording with this version of CueCan."
        case .newerFormat(let url, let version):
            "\(url.lastPathComponent) was saved by a newer version of CueCan (format \(version)). Update CueCan to open it."
        case .couldNotRead(let url, let reason):
            "Couldn't read \(url.lastPathComponent): \(reason)"
        case .unreadable(let url, let reason):
            "\(url.lastPathComponent) is damaged or isn't in the expected format: \(reason)"
        case .couldNotWrite(let url, let reason):
            "Couldn't save \(url.lastPathComponent): \(reason)"
        case .couldNotLock(let url, let reason):
            "Couldn't get access to the project “\(url.lastPathComponent)”: \(reason)"
        case .unfinishedChange(let url, let reason):
            "The last change to “\(url.lastPathComponent)” didn't finish saving, and CueCan can't finish it (\(reason)). Some files may already contain part of the change. Nothing more can be saved until it's finished. Keep .pending-mutation.json in the project folder; CueCan needs it to finish saving."
        case .alreadyTranscribed(let source):
            "Source \(source) already has a transcript. Transcripts never change once written."
        case .nothingToUndo:
            "There's nothing to undo."
        case .nothingToRedo:
            "There's nothing to redo."
        case .unknownHistoryEntry(let sequence):
            "There's no change number \(sequence) in this project's history."
        }
    }
}

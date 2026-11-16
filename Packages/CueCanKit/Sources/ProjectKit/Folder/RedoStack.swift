import Foundation

/// What can be redone: the edit as it was before each undo, newest last, in `history/redo.json`.
///
/// An undo pushes the edit it replaced; a redo puts it back as a new change, so the redo can itself be
/// undone. Any other change clears it, as in every editor.
struct RedoStack: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var edit: Edit
        /// What the undone changes were.
        var reason: String
        var author: EditAuthor
    }

    let url: URL

    func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try ProjectJSON.decoder.decode([Entry].self, from: Data(contentsOf: url))
    }

    func save(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectJSON.encoder.encode(entries).write(to: url, options: .atomic)
    }

    /// What can be redone, for an undo about to add to it. An unreadable file mustn't stop the undo, and
    /// mustn't be overwritten either: it's moved aside, as `redo-unreadable-<time>.json` beside it, and the
    /// undo starts a fresh list. Call with the project lock held.
    func entriesForUndo() throws -> [Entry] {
        do {
            return try entries()
        } catch {
            let stamp = Int(Date.now.timeIntervalSince1970 * 1000)
            let aside = url.deletingLastPathComponent().appending(path: "redo-unreadable-\(stamp).json")
            try FileManager.default.moveItem(at: url, to: aside)
            return []
        }
    }

}

extension ProjectFolder {
    var redoStack: RedoStack { RedoStack(url: url(for: .history).appending(path: "redo.json")) }

    /// Whether an undo can be redone.
    public var canRedo: Bool { (try? !redoStack.entries().isEmpty) ?? false }

    /// What the next redo would put back, such as "Cut w_12…w_20".
    public var redoReason: String? { try? redoStack.entries().last?.reason }

    /// Redoes the latest undo: puts the edit back as it was before it, as a new change that can be undone.
    @discardableResult
    public func redo(author: EditAuthor) throws -> Edit {
        try withLock {
            var remaining = try redoStack.entries()
            guard let entry = remaining.popLast() else { throw ProjectFolderError.nothingToRedo }
            let current = try loadEdit()
            var edit = entry.edit
            edit.nextClipNumber = max(edit.nextClipNumber, current.nextClipNumber)
            return try saveEdit(edit, replacing: current, author: author, reason: "Redo: \(entry.reason)", redo: remaining)
        }
    }
}

import Foundation

/// The snapshots in a project's `history/` folder: the edit as it was before each change, with who made
/// the change and why.
///
/// Each snapshot is `history/<sequence>.json`, numbered from 1 in the order the changes were made.
/// Undoing moves snapshots into `history/undone/` rather than deleting them.
public struct EditHistory: Sendable {
    /// A snapshot file: the edit before one change.
    public struct Entry: Codable, Equatable, Sendable {
        public var sequence: Int
        public var savedAt: Date
        public var author: EditAuthor
        public var reason: String
        /// The edit as it was before the change.
        public var edit: Edit
    }

    public let folder: URL

    /// Every snapshot still in effect, oldest first.
    public func entries() throws -> [Entry] {
        try sequences().map { try entry($0) }
    }

    /// Every snapshot still in effect as its file holds it, oldest first, without decoding any.
    ///
    /// Reading the files is quick and decoding them is not, so a caller that needs the project's lock for
    /// a consistent reading takes these under it and decodes them with `entry(decoding:)` after letting go.
    public func storedEntries() throws -> [Data] {
        try sequences().map { try Data(contentsOf: url(for: $0)) }
    }

    /// A snapshot from what `storedEntries()` read.
    public static func entry(decoding stored: Data) throws -> Entry {
        try ProjectJSON.decoder.decode(Entry.self, from: stored)
    }

    /// Undo only needs the snapshots being removed, not every earlier edit's full contents.
    func entries(from sequence: Int) throws -> [Entry] {
        try sequences().filter { $0 >= sequence }.map { try entry($0) }
    }

    /// The sequence number of the latest snapshot still in effect, without reading any of them.
    public func latestSequence() throws -> Int? {
        try sequences().last
    }

    /// One snapshot.
    public func entry(_ sequence: Int) throws -> Entry {
        let fileURL = url(for: sequence)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw ProjectFolderError.unknownHistoryEntry(sequence)
        }
        return try Self.entry(decoding: Data(contentsOf: fileURL))
    }

    /// Reserves a sequence before the mutation is journaled. Gaps after a failed save are harmless.
    func prepare(snapshotOf edit: Edit, author: EditAuthor, reason: String) throws -> Entry {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return Entry(sequence: try nextSequence(), savedAt: .now, author: author, reason: reason, edit: edit)
    }

    /// Replaying a pending mutation writes the same snapshot at the same sequence.
    func save(_ entry: Entry) throws {
        try ProjectJSON.encoder.encode(entry).write(to: url(for: entry.sequence), options: .atomic)
    }

    /// Moves the snapshot `sequence` and every later one into `history/undone/`.
    ///
    /// Safe to run again after an interruption, because a pending undo is replayed: a snapshot already
    /// moved is no longer in `history/`. A name already taken in `undone/` doesn't stop it. That can
    /// happen if the `.next` counter was lost and a number was used twice. An identical file there means
    /// this one was already archived, so it's removed; a different one keeps both, with a suffix.
    func moveToUndone(from sequence: Int) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: undoneFolder, withIntermediateDirectories: true)
        for later in try sequences() where later >= sequence {
            let source = url(for: later).path(percentEncoded: false)
            let name = Self.fileName(for: later)
            var destination = undoneFolder.appending(path: "\(name).json").path(percentEncoded: false)
            var copy = 1
            while fileManager.fileExists(atPath: destination), !fileManager.contentsEqual(atPath: source, andPath: destination) {
                copy += 1
                destination = undoneFolder.appending(path: "\(name)-\(copy).json").path(percentEncoded: false)
            }
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: source)
            } else {
                try fileManager.moveItem(atPath: source, toPath: destination)
            }
        }
    }

    // MARK: - Files

    /// Sequence numbers keep counting after an undo, so a snapshot's number is never reused. The counter
    /// file is the record, but if it's lost, such as by a copy that skips hidden files, counting carries on
    /// past every snapshot still on disk, undone ones included.
    private func nextSequence() throws -> Int {
        let counterURL = folder.appending(path: ".next")
        let stored = (try? String(contentsOf: counterURL, encoding: .utf8)).flatMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let highest = max(try sequences().last ?? 0, try undoneSequences().max() ?? 0)
        let next = max(stored ?? 1, highest + 1)
        try String(next + 1).write(to: counterURL, atomically: true, encoding: .utf8)
        return next
    }

    private func sequences() throws -> [Int] {
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .compactMap { name in
                guard name.hasSuffix(".json") else { return nil }
                return Int(name.dropLast(5))
            }
            .sorted()
    }

    private var undoneFolder: URL { folder.appending(path: "undone", directoryHint: .isDirectory) }

    /// The numbers of the undone snapshots, from names such as `000002.json`, `000002-2.json`, or
    /// `000002-1730851200000.json` from earlier builds.
    private func undoneSequences() throws -> [Int] {
        guard FileManager.default.fileExists(atPath: undoneFolder.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: undoneFolder.path(percentEncoded: false))
            .compactMap { name in
                guard name.hasSuffix(".json") else { return nil }
                return Int(name.dropLast(5).prefix { $0 != "-" })
            }
    }

    private func url(for sequence: Int) -> URL {
        folder.appending(path: "\(Self.fileName(for: sequence)).json")
    }

    /// Zero-padded so snapshots sort by name in Finder.
    private static func fileName(for sequence: Int) -> String {
        let digits = String(sequence)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

}

import Foundation

/// Replaces the closed recordings with their staged cuts as one group.
enum TrackTrimPublication {
    /// Originals that could not be restored remain beside their recovery copies. The caller must not
    /// save original clock metadata against a mixture of cut and uncut files.
    struct RestorationFailure: Error, LocalizedError {
        let files: [URL]
        let reason: String

        var errorDescription: String? {
            "Couldn't finish saving the recording or restore all its files. Recovery copies of the original recordings are kept in \(files.first?.deletingLastPathComponent().path(percentEncoded: false) ?? "the recording folder"). \(reason)"
        }
    }

    static func replace(_ files: [(original: URL, copy: URL)],
                        restore: (URL, URL) throws -> Void = { original, copy in
                            if FileManager.default.fileExists(atPath: original.path) {
                                _ = try FileManager.default.replaceItemAt(original, withItemAt: copy)
                            } else {
                                try FileManager.default.moveItem(at: copy, to: original)
                            }
                        },
                        publish: (URL, URL) throws -> Void = { original, copy in
                            _ = try FileManager.default.replaceItemAt(original, withItemAt: copy)
                        }) throws {
        let manager = FileManager.default
        var backups: [(original: URL, copy: URL)] = []
        defer {
            for file in files { try? manager.removeItem(at: file.copy) }
        }
        // Make recovery copies before touching any original. A failed replace can move its original
        // before it throws, so even the replacement that failed must be restored.
        do {
            for file in files {
                let backup = file.original.deletingLastPathComponent()
                    .appending(path: "untrimmed-\(UUID())-\(file.original.lastPathComponent)")
                backups.append((file.original, backup))
                try manager.copyItem(at: file.original, to: backup)
            }
        } catch {
            for backup in backups { try? manager.removeItem(at: backup.copy) }
            throw error
        }
        do {
            for file in files { try publish(file.original, file.copy) }
        } catch {
            let publicationError = error
            var unrestored: [URL] = []
            var reasons: [String] = []
            for backup in backups.reversed() {
                let staged = backup.original.deletingLastPathComponent()
                    .appending(path: "restoring-\(UUID())-\(backup.original.lastPathComponent)")
                defer { try? manager.removeItem(at: staged) }
                do {
                    // A failed restoration can also consume its input. Keep the recovery copy intact
                    // until every original has been restored, and only replace from a disposable copy.
                    try manager.copyItem(at: backup.copy, to: staged)
                    try restore(backup.original, staged)
                } catch {
                    unrestored.append(backup.original)
                    reasons.append(error.localizedDescription)
                }
            }
            if !unrestored.isEmpty {
                throw RestorationFailure(files: unrestored, reason: reasons.joined(separator: "; "))
            }
            for backup in backups { try? manager.removeItem(at: backup.copy) }
            throw publicationError
        }
        for backup in backups { try? manager.removeItem(at: backup.copy) }
    }
}

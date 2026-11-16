import Foundation

/// Publishes an app export from its private folder without replacing a file that appeared after the
/// creator reviewed the name. Files in one completion group move together or are moved back on failure.
public enum ExportPublication {
    public static func publish(_ files: [URL], to folder: URL, fileManager: FileManager = .default) throws -> [URL] {
        var moved: [(source: URL, destination: URL)] = []
        do {
            for source in files {
                try Task.checkCancellation()
                let destination = folder.appending(path: source.lastPathComponent)
                // moveItem itself refuses an existing destination; there is no delete-and-rename race.
                try fileManager.moveItem(at: source, to: destination)
                moved.append((source, destination))
            }
            return moved.map(\.destination)
        } catch {
            for file in moved.reversed() {
                do { try fileManager.moveItem(at: file.destination, to: file.source) }
                catch {
                    throw RenderError.exportFailed("Couldn't finish saving the export. Some files remain in \(folder.path(percentEncoded: false)): \(error.localizedDescription)")
                }
            }
            throw error
        }
    }
}

import Foundation
import ProjectKit

/// Retains the cleaned audio captured by a waiting export. Processing may remove superseded cleanup
/// files; hard links on the project's volume preserve their bytes without copying a recording.
/// The owner releases these links after completion or cancellation, including queued cancellation.
public struct ExportAudioSnapshot: Sendable {
    public let inputs: RenderInputs
    private let directory: URL?

    public static func capture(_ inputs: RenderInputs) throws -> Self {
        let audioFolder = inputs.folder.url(for: .audio)
        let cleaned = inputs.primaryAudio.filter {
            $0.value.deletingLastPathComponent().standardizedFileURL.pathComponents == audioFolder.standardizedFileURL.pathComponents
        }
        guard !cleaned.isEmpty else { return Self(inputs: inputs, directory: nil) }
        return try inputs.folder.withLock {
            let manager = FileManager.default
            // Keep it outside audio/: changing that directory's date would rebuild a playing preview.
            let directory = inputs.folder.url.appending(path: ".export-inputs-\(UUID())", directoryHint: .isDirectory)
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: false)
                var audio = inputs.primaryAudio
                for (source, original) in cleaned {
                    let retained = directory.appending(path: "\(source)-\(original.lastPathComponent)")
                    try manager.linkItem(at: original, to: retained)
                    audio[source] = retained
                }
                return Self(inputs: RenderInputs(folder: inputs.folder, project: inputs.project, edit: inputs.edit,
                                                 transcripts: inputs.transcripts, spellings: inputs.spellings, primaryAudio: audio,
                                                 levels: inputs.levels),
                            directory: directory)
            } catch {
                try? manager.removeItem(at: directory)
                throw RenderError.exportFailed("Couldn't keep the audio for this export. Try exporting again. \(error.localizedDescription)")
            }
        }
    }

    /// Removes only this export's links. Original recordings and the current cleanup remain untouched.
    public func release() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }
}

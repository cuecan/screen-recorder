import Foundation

/// Why a preview, a still or an export couldn't be made. Messages can reach the app and Claude.
public enum RenderError: Error, Equatable, Sendable, LocalizedError {
    case emptyEdit
    case missingFile(URL)
    case unreadableFile(URL, String)
    case noPicture
    case exportFailed(String)
    case couldNotEncodeImage

    public var errorDescription: String? {
        switch self {
        case .emptyEdit:
            "The edit has no clips yet, so there's nothing to play. Add a clip first."
        case .missingFile(let url):
            "Couldn't find \(url.lastPathComponent) at \(url.deletingLastPathComponent().path(percentEncoded: false)). If it was moved, put it back."
        case .unreadableFile(let url, let reason):
            "Couldn't read \(url.lastPathComponent): \(reason)"
        case .noPicture:
            "The edit has no video to show."
        case .exportFailed(let reason):
            "The export didn't finish: \(reason)"
        case .couldNotEncodeImage:
            "Couldn't save the still as an image."
        }
    }
}

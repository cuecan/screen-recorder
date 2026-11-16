import Foundation
import ProjectKit

/// Why a source couldn't be transcribed or cleaned. The messages can reach the app and Claude.
public enum ProcessingError: Error, Equatable, Sendable, LocalizedError {
    case noAudio(SourceID)
    case missingFile(URL)

    public var errorDescription: String? {
        switch self {
        case .noAudio(let source):
            "Source \(source) has no sound to transcribe or clean."
        case .missingFile(let url):
            "Couldn't find \(url.lastPathComponent) at \(url.deletingLastPathComponent().path(percentEncoded: false))."
        }
    }
}

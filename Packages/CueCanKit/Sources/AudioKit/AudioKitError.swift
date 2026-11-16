import Foundation

/// Why audio couldn't be read, written, converted or cleaned, in words a creator understands.
public enum AudioKitError: Error, Equatable, Sendable, LocalizedError {
    case noAudioTrack(URL)
    case trackOutOfRange(URL, requested: Int, available: Int)
    case unreadable(URL, String)
    case couldNotWrite(URL, String)
    case conversionFailed(String)
    case modelFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .noAudioTrack(let url):
            "“\(url.lastPathComponent)” has no sound to work with."
        case .trackOutOfRange(let url, let requested, let available):
            "“\(url.lastPathComponent)” has \(available) audio track\(available == 1 ? "" : "s"), so there's no track \(requested)."
        case .unreadable(let url, let reason):
            "Couldn't read the sound in “\(url.lastPathComponent)”: \(reason)"
        case .couldNotWrite(let url, let reason):
            "Couldn't save “\(url.lastPathComponent)”: \(reason)"
        case .conversionFailed(let reason):
            "Couldn't convert the audio: \(reason)"
        case .modelFailed(let model, let reason):
            "\(model) couldn't process the audio: \(reason)"
        }
    }
}

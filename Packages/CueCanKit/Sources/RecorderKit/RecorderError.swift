import Foundation

/// Why recording couldn't start or finish. The messages reach the widget, so they say what to do.
public enum RecorderError: Error, Equatable, Sendable, LocalizedError {
    case noScreenRecordingPermission
    case displayNotFound
    case noCamera
    case noMicrophone
    case permissionDenied(String)
    case couldNotUseDevice(String, String)
    case couldNotWrite(URL, String)
    case unexpectedBuffer
    case nothingRecorded
    case finalizationFailed([String])
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .noScreenRecordingPermission:
            "CueCan needs Screen Recording access. Turn it on in System Settings."
        case .displayNotFound:
            "The display under the area was disconnected."
        case .noCamera:
            "There's no camera connected."
        case .noMicrophone:
            "There's no microphone connected."
        case .permissionDenied(let what):
            "CueCan needs access to the \(what). Turn it on in System Settings."
        case .couldNotUseDevice(let name, let reason):
            "Couldn't use \(name): \(reason)"
        case .couldNotWrite(let url, let reason):
            "Couldn't write \(url.lastPathComponent): \(reason)"
        case .unexpectedBuffer:
            "A capture device sent something CueCan couldn't record."
        case .nothingRecorded:
            "Nothing was recorded. Check that each source is live in the widget, then record again."
        case .finalizationFailed(let failures):
            "Couldn’t finish the recording: " + failures.joined(separator: "; ")
        case .alreadyRecording:
            "A recording is already running."
        }
    }
}

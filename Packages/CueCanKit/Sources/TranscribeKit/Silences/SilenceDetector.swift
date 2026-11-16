import AudioKit
import Foundation
import ProjectKit

/// Finds the real silences in a recording: the places where the audio itself is quiet, and so where a cut
/// can't clip a word.
public protocol SilenceDetector: AnyObject {
    /// A short stable name, recorded in the transcript, such as `energy`.
    var id: String { get }
    func load(progress: @escaping @Sendable (String) -> Void) async throws
    /// The silences, in order, without overlaps.
    func silences(in audio: AudioSamples) async throws -> [TimeRange]
    func unload()
}

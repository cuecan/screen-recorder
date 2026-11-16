import AudioKit
import Foundation

/// A pipeline that writes the words of a recording and places each one in time.
///
/// Two are used (docs/decisions.md, 39): Parakeet writes the primary transcript, with every repeat and filler,
/// and Apple's SpeechAnalyzer gives a second reading where the two disagree. Models are loaded explicitly,
/// since loading downloads weights on first use, and unloaded when done. An engine is used from one task at
/// a time.
public protocol TranscriptionEngine: AnyObject {
    /// A short stable name for files and transcripts, such as `parakeet-tdt-v3`.
    var id: String { get }
    var displayName: String { get }
    /// What it downloads on first use.
    var weightsDescription: String { get }
    /// The longest audio to hand it at once. Longer audio is split at silences first (``Transcriber``).
    /// Nil if the engine takes any length.
    var maximumChunkDuration: TimeInterval? { get }

    func load(progress: @escaping @Sendable (String) -> Void) async throws
    /// The words in `audio`, with times in seconds from its start.
    ///
    /// - Parameter language: A BCP 47 code such as `en`, or nil to let the engine detect it.
    func transcribe(_ audio: AudioSamples, language: String?) async throws -> [TimedWord]
    func unload()
}

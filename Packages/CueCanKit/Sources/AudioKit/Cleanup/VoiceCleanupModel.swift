import Foundation
import ProjectKit

/// A speech model that cleans a voice after recording: one candidate in the cleanup bake-off.
///
/// Models are loaded explicitly, since loading downloads weights on first use, and unloaded when done,
/// so the bake-off can run one candidate after another without holding them all in memory. A model is
/// used from one task at a time.
public protocol VoiceCleanupModel: AnyObject {
    /// A short stable name for files and reports, such as `soundisolation`.
    var id: String { get }
    /// The name to show, such as "AUSoundIsolation".
    var displayName: String { get }
    /// What it downloads on first use, such as a Hugging Face model id.
    var weightsDescription: String { get }
    /// How Cleanup's Amount dial works with this model (docs/decisions.md, 34).
    var amountControl: CleanupAmountControl { get }

    /// Downloads the weights if needed, then loads them.
    func load(progress: @escaping @Sendable (String) -> Void) async throws
    /// Cleans the audio fully. The original is never touched; this returns new samples.
    func clean(_ audio: AudioSamples) async throws -> AudioSamples
    /// Cleans the audio at an amount from 0 to 100 percent. Only a model whose ``amountControl`` is
    /// ``CleanupAmountControl/native`` uses the amount. The others clean fully, and the amount is a blend
    /// with the original, applied afterwards.
    func clean(_ audio: AudioSamples, amount: Double) async throws -> AudioSamples
    /// Frees the weights.
    func unload()
}

extension VoiceCleanupModel {
    public var amountControl: CleanupAmountControl { .blend }

    public func clean(_ audio: AudioSamples, amount: Double) async throws -> AudioSamples {
        try await clean(audio)
    }
}

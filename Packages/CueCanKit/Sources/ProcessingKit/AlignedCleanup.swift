import AudioKit
import ProjectKit

/// The shared Cleanup pipeline for preview audio and editor handoff. Alignment never changes gain.
enum AlignedCleanup {
    static func apply(_ settings: CleanupSettings, to original: AudioSamples) async throws -> AudioSamples {
        guard settings.mode == .natural else { return original }
        let cleaned = try await SoundIsolationCleanup().clean(original, amount: settings.amount).resampled(to: original.sampleRate)
        let measured = SignalAlignment.measure(original: original, processed: cleaned)
        return SignalAlignment(lag: measured.lag, correlation: measured.correlation, gain: 1)
            .apply(to: cleaned, length: original.samples.count)
    }
}

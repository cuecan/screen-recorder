import Foundation
import Testing
@testable import AudioKit

/// `AUSoundIsolation` is part of macOS, so this runs without hardware. It records the answer to a VERIFY
/// item in docs/design.md: whether the unit renders in AVAudioEngine's offline mode.
@Suite struct SoundIsolationTests {
    @Test func rendersOfflineAtAnyAmount() async throws {
        let model = SoundIsolationCleanup()
        try await model.load(progress: { _ in })
        let input = AudioSamples(samples: Signal.sine(frequency: 220, peakDecibels: -12, duration: 1), sampleRate: 48_000)
        for amount in [0.0, 50, 100] {
            let output = try await model.clean(input, amount: amount)
            #expect(output.sampleRate == 48_000)
            // It renders past the input's end, so its latency and tail come out too.
            #expect(output.samples.count > input.samples.count)
            #expect(output.samples.allSatisfy { $0.isFinite })
        }
    }
}


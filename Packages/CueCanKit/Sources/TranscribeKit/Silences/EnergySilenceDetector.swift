import AudioKit
import Foundation
import ProjectKit

/// Finds silences from the audio's energy, with no model.
///
/// The level of each short frame is measured in dB. The recording's own noise floor (a low percentile of
/// frame levels) and speech level (a high percentile) set the threshold between them, so it adapts to a
/// quiet studio and a noisy room alike. Quiet runs shorter than ``Settings/minimumSilence`` are speech
/// gaps, not silences. Loud blips shorter than ``Settings/minimumSound`` inside a silence, such as a
/// click, don't break it.
public final class EnergySilenceDetector: SilenceDetector {
    /// Starting values, to tune by ear in the bake-off (TEST NEEDED). None of them is measured.
    public struct Settings: Sendable, Equatable {
        public var frameDuration: TimeInterval
        public var minimumSilence: TimeInterval
        public var minimumSound: TimeInterval
        /// Where the threshold sits between the noise floor (0) and the speech level (1).
        public var thresholdPosition: Double
        public var noiseFloorPercentile: Double
        public var speechLevelPercentile: Double

        public init(
            frameDuration: TimeInterval = 0.01,
            minimumSilence: TimeInterval = 0.2,
            minimumSound: TimeInterval = 0.03,
            thresholdPosition: Double = 0.25,
            noiseFloorPercentile: Double = 0.1,
            speechLevelPercentile: Double = 0.95
        ) {
            self.frameDuration = frameDuration
            self.minimumSilence = minimumSilence
            self.minimumSound = minimumSound
            self.thresholdPosition = thresholdPosition
            self.noiseFloorPercentile = noiseFloorPercentile
            self.speechLevelPercentile = speechLevelPercentile
        }
    }

    public let id = "energy"
    public let settings: Settings

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {}
    public func unload() {}

    public func silences(in audio: AudioSamples) async throws -> [TimeRange] {
        detect(in: audio)
    }

    /// What the detector measured: each frame's level, the threshold between quiet and sound, and the
    /// silences. Word fitting reads the levels too (``WordFitter``).
    public struct Analysis: Sendable {
        /// Each frame's level, in dB.
        public var envelope: SoundEnvelope
        /// Frames below this level, in dB, are quiet.
        public var threshold: Double
        public var silences: [TimeRange]
        public var duration: TimeInterval
    }

    /// The same as ``silences(in:)``, synchronously.
    public func detect(in audio: AudioSamples) -> [TimeRange] {
        analyze(audio).silences
    }

    /// Measures the audio and finds its silences.
    public func analyze(_ audio: AudioSamples) -> Analysis {
        let frameLength = max(1, Int((settings.frameDuration * audio.sampleRate).rounded()))
        let frameCount = audio.samples.count / frameLength
        guard frameCount > 0 else {
            return Analysis(envelope: SoundEnvelope(levels: [], frameDuration: settings.frameDuration), threshold: 0, silences: [], duration: audio.duration)
        }
        let frameSeconds = Double(frameLength) / audio.sampleRate

        var levels = [Double](repeating: 0, count: frameCount)
        audio.samples.withUnsafeBufferPointer { samples in
            for frame in 0..<frameCount {
                var sum = 0.0
                for index in (frame * frameLength)..<((frame + 1) * frameLength) {
                    let value = Double(samples[index])
                    sum += value * value
                }
                levels[frame] = 10 * log10(sum / Double(frameLength) + 1e-12)
            }
        }

        let sorted = levels.sorted()
        let floor = Self.percentile(sorted, settings.noiseFloorPercentile)
        let speech = Self.percentile(sorted, settings.speechLevelPercentile)
        let threshold = floor + max(3, (speech - floor) * settings.thresholdPosition)

        var quiet = levels.map { $0 < threshold }
        let minimumSoundFrames = Int((settings.minimumSound / frameSeconds).rounded())
        Self.fillShortRuns(of: false, in: &quiet, shorterThan: minimumSoundFrames)

        let minimumSilenceFrames = Int((settings.minimumSilence / frameSeconds).rounded(.up))
        var silences: [TimeRange] = []
        var runStart: Int?
        for frame in 0...frameCount {
            let isQuiet = frame < frameCount && quiet[frame]
            if isQuiet, runStart == nil {
                runStart = frame
            } else if !isQuiet, let start = runStart {
                if frame - start >= minimumSilenceFrames {
                    let end = frame == frameCount ? audio.duration : Double(frame) * frameSeconds
                    silences.append(TimeRange(start: Double(start) * frameSeconds, end: end))
                }
                runStart = nil
            }
        }
        return Analysis(envelope: SoundEnvelope(levels: levels, frameDuration: frameSeconds), threshold: threshold,
                        silences: silences, duration: audio.duration)
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let position = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[min(sorted.count - 1, max(0, position))]
    }

    /// Flips runs of `value` shorter than `length` that sit between runs of the other value.
    static func fillShortRuns(of value: Bool, in flags: inout [Bool], shorterThan length: Int) {
        guard length > 0 else { return }
        var index = 0
        while index < flags.count {
            guard flags[index] == value else {
                index += 1
                continue
            }
            var end = index
            while end < flags.count, flags[end] == value { end += 1 }
            let bounded = index > 0 && end < flags.count
            if bounded, end - index < length {
                for flip in index..<end { flags[flip] = !value }
            }
            index = end
        }
    }
}

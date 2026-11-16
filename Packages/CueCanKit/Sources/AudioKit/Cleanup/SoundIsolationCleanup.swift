import AVFoundation
import AudioToolbox
import Foundation
import ProjectKit

/// Apple's `AUSoundIsolation`, the audio unit behind Voice Isolation, rendered offline through
/// `AVAudioEngine`'s manual rendering mode. A candidate for Natural, built into macOS with nothing to
/// download (docs/design.md, "Audio and transcripts").
///
/// It uses the high-quality voice sound type (macOS 15), and its own wet/dry mix as the Amount dial.
/// Whether it renders offline at all was VERIFY: if it can't, ``clean(_:amount:)`` throws and says so.
public final class SoundIsolationCleanup: VoiceCleanupModel {
    public let id = "soundisolation"
    public let displayName = "AUSoundIsolation"
    public let weightsDescription = "nothing: built into macOS"
    public let amountControl = CleanupAmountControl.native

    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_AUSoundIsolation,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )

    /// The rate the unit is run at.
    static let sampleRate = 48_000.0

    public init() {}

    public func load(progress: @escaping @Sendable (String) -> Void) async throws {
        // Instantiating once checks the unit exists on this Mac before any audio is rendered.
        _ = try await makeUnit()
    }

    public func unload() {}

    public func clean(_ audio: AudioSamples) async throws -> AudioSamples {
        try await clean(audio, amount: 100)
    }

    public func clean(_ audio: AudioSamples, amount: Double) async throws -> AudioSamples {
        try Task.checkCancellation()
        let input = try audio.resampled(to: Self.sampleRate)
        guard !input.samples.isEmpty else { return input }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            throw AudioKitError.modelFailed(displayName, "Couldn't describe a mono 48 kHz format.")
        }
        let unit = try await makeUnit()
        try setParameter(kAUSoundIsolationParam_SoundToIsolate, to: AudioUnitParameterValue(kAUSoundIsolationSoundType_HighQualityVoice), on: unit)
        try setParameter(kAUSoundIsolationParam_WetDryMixPercent, to: AudioUnitParameterValue(min(100, max(0, amount))), on: unit)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(unit)
        engine.connect(player, to: unit, format: format)
        engine.connect(unit, to: engine.mainMixerNode, format: format)

        let maximumFrames: AVAudioFrameCount = 4096
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrames)
            try engine.start()
        } catch {
            throw AudioKitError.modelFailed(displayName, "AVAudioEngine wouldn't start offline rendering: \(error.localizedDescription)")
        }
        defer { engine.stop() }

        guard let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.samples.count)),
            let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maximumFrames)
        else {
            throw AudioKitError.modelFailed(displayName, "Couldn't allocate audio buffers.")
        }
        source.frameLength = source.frameCapacity
        input.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { source.floatChannelData?[0].update(from: base, count: samples.count) }
        }
        Self.schedule(source, on: player)
        player.play()

        // Render past the end so the unit's latency and tail come out too. SignalAlignment trims them.
        let tail = Int(Self.sampleRate) + Int((unit.auAudioUnit.latency + unit.auAudioUnit.tailTime) * Self.sampleRate)
        let total = input.samples.count + tail
        var rendered: [Float] = []
        rendered.reserveCapacity(total)
        var progress = OfflineRenderProgress(totalFrames: total, renderer: displayName)
        while !progress.isFinished {
            try Task.checkCancellation()
            let before = rendered.count
            let frames = min(maximumFrames, AVAudioFrameCount(total - rendered.count))
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(frames, to: output)
            } catch {
                throw AudioKitError.modelFailed(displayName, "Offline rendering failed: \(error.localizedDescription)")
            }
            switch status {
            case .success, .insufficientDataFromInputNode:
                if let channel = output.floatChannelData?[0] {
                    rendered.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
                }
            case .cannotDoInCurrentContext:
                // Give whatever holds the engine a moment; OfflineRenderProgress gives up after enough tries.
                try await Task.sleep(for: OfflineRenderProgress.retryDelay)
            case .error:
                throw AudioKitError.modelFailed(displayName, "It doesn't render in AVAudioEngine's offline mode.")
            @unknown default:
                throw AudioKitError.modelFailed(displayName, "Offline rendering returned an unknown status.")
            }
            try progress.advance(by: rendered.count - before)
        }
        return AudioSamples(samples: rendered, sampleRate: Self.sampleRate)
    }

    /// Queues the whole input. The async form of `scheduleBuffer` waits for playback to finish, which in
    /// offline rendering only happens as the render loop below pulls the audio through, so it can't be
    /// awaited here.
    private static func schedule(_ buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode) {
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func makeUnit() async throws -> AVAudioUnit {
        do {
            return try await AVAudioUnit.instantiate(with: Self.description, options: [])
        } catch {
            throw AudioKitError.modelFailed(displayName, "macOS didn't provide the unit: \(error.localizedDescription)")
        }
    }

    private func setParameter(_ parameter: AudioUnitParameterID, to value: AudioUnitParameterValue, on unit: AVAudioUnit) throws {
        let status = AudioUnitSetParameter(unit.audioUnit, parameter, kAudioUnitScope_Global, 0, value, 0)
        guard status == noErr else {
            throw AudioKitError.modelFailed(displayName, "Couldn't set parameter \(parameter) (\(status)).")
        }
    }
}

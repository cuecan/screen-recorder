import Foundation

/// One of the editor's two on-and-off switches over the takes' voice processing (docs/ui.md, E6): noise
/// reduction, which is Cleanup, and the equalizer, which is the Voice preset. Each acts on every mic the
/// edit plays, so one click hears the video with or without it.
public enum AudioSwitch: String, Sendable, CaseIterable {
    case noiseReduction, equalizer

    public var title: String {
        switch self {
        case .noiseReduction: "Noise reduction"
        case .equalizer: "Equalizer"
        }
    }

    /// Whether one mic has it on.
    public func isOn(_ settings: SourceAudioSettings) -> Bool {
        switch self {
        case .noiseReduction: settings.cleanup.mode != .off
        case .equalizer: settings.voice.preset != .off
        }
    }

    /// Whether every one of these mics has it on. Off when there are none, or when they differ: a click then
    /// turns it on for all of them.
    public func isOn(for sources: [SourceID], in audio: AudioSettings) -> Bool {
        !sources.isEmpty && sources.allSatisfy { isOn(audio.settings(for: $0)) }
    }

    /// Switches one mic, leaving its amount. The equalizer comes back with `preset`, the one it had before it
    /// was switched off; Clear when that isn't known.
    public func set(_ on: Bool, in settings: inout SourceAudioSettings, restoring preset: VoiceSettings.Preset = .clear) {
        switch self {
        case .noiseReduction:
            settings.cleanup.mode = on ? .natural : .off
        case .equalizer:
            if !on { settings.voice.preset = .off }
            else if settings.voice.preset == .off { settings.voice.preset = preset == .off ? .clear : preset }
        }
    }
}

extension AudioSettings {
    /// Switches every one of these mics. True when anything changed.
    @discardableResult
    public mutating func set(_ audioSwitch: AudioSwitch, on: Bool, for sources: [SourceID],
                             restoring presets: [SourceID: VoiceSettings.Preset] = [:]) -> Bool {
        var changed = false
        for source in sources {
            var settings = self.settings(for: source)
            let before = settings
            audioSwitch.set(on, in: &settings, restoring: presets[source] ?? .clear)
            guard settings != before else { continue }
            set(settings, for: source)
            changed = true
        }
        return changed
    }
}

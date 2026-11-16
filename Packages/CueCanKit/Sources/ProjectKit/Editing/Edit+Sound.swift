import Foundation

/// A change to clips' sound (docs/decisions.md, 71): any of the voice's level, system audio's level and
/// Mute. What's left nil stays as each clip has it.
public struct ClipSoundChange: Equatable, Sendable {
    /// The voice's level, in dB.
    public var voiceLevel: Double?
    /// System audio's level, in dB.
    public var systemAudioLevel: Double?
    public var isMuted: Bool?

    public init(voiceLevel: Double? = nil, systemAudioLevel: Double? = nil, isMuted: Bool? = nil) {
        self.voiceLevel = voiceLevel
        self.systemAudioLevel = systemAudioLevel
        self.isMuted = isMuted
    }

    /// Whether it changes nothing.
    public var isEmpty: Bool { voiceLevel == nil && systemAudioLevel == nil && isMuted == nil }
}

extension Edit {
    /// Sets the sound of one or more clips: levels in dB, clamped to ``SoundLevel/range``, and Mute. The
    /// operation behind the level line, the inspector's Sound section and `set_clip_sound`.
    ///
    /// Every clip id is checked before anything changes, so an unknown one changes nothing.
    public mutating func setSound(_ change: ClipSoundChange, for clipIDs: [ClipID]) throws(EditError) {
        var indices: [Int] = []
        for id in clipIDs {
            guard let index = main.firstIndex(where: { $0.id == id }) else { throw .unknownClip(id) }
            indices.append(index)
        }
        for index in indices {
            if let level = change.voiceLevel { main[index].voiceLevel = level }
            if let level = change.systemAudioLevel { main[index].systemAudioLevel = level }
            if let muted = change.isMuted { main[index].isMuted = muted }
        }
    }

    /// Sets the level of an overlay's own sound, in dB.
    public mutating func setLevel(_ level: Double, forOverlay id: ClipID) throws(EditError) {
        try updateOverlay(id) { $0.level = level }
    }
}

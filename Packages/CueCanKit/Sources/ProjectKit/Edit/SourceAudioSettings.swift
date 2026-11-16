import Foundation

/// Cleanup and Voice for one mic source, or the project's default for all of them.
public struct SourceAudioSettings: Codable, Equatable, Sendable {
    public var cleanup: CleanupSettings
    public var voice: VoiceSettings

    public init(cleanup: CleanupSettings = CleanupSettings(), voice: VoiceSettings = VoiceSettings()) {
        self.cleanup = cleanup
        self.voice = voice
    }
}

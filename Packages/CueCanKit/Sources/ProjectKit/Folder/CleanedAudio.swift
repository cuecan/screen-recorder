import Foundation

/// A mic source's cleaned voice in `audio/`: what Cleanup and Voice made from it, and with which settings.
///
/// Stored as `audio/<source>.json` beside the file. The file is regenerable: when the source's settings
/// change, the record no longer matches, and the preview and export use the raw mic until it's cleaned again.
public struct CleanedAudio: Codable, Equatable, Sendable {
    public enum Purpose: Sendable { case preview, handoff }

    /// Each generation gets a unique file. Publishing a new sidecar never overwrites audio in use.
    public static func newFileName(for source: SourceID, settings: SourceAudioSettings) -> String {
        String(fileName(for: source, settings: settings).dropLast(4)) + "-" + UUID().uuidString + ".wav"
    }

    public var source: SourceID
    /// The settings it was made with.
    public var settings: SourceAudioSettings
    /// The cleaned file's name in `audio/`.
    public var file: String
    /// The track it was made from, so a cleaned file is never used for another track.
    public var original: FileReference
    public var createdAt: Date

    public init(source: SourceID, settings: SourceAudioSettings, file: String, original: FileReference, createdAt: Date = .now) {
        self.source = source
        self.settings = settings
        self.file = file
        self.original = original
        self.createdAt = createdAt
    }

    /// A file name for these settings, such as `src_1-natural75-clear50.wav`. Each setting gets its own
    /// file, so a new one never overwrites a file the preview may be playing.
    public static func fileName(for source: SourceID, settings: SourceAudioSettings) -> String {
        func amount(_ value: Double) -> String { String(Int(value.rounded())) }
        let cleanup = settings.cleanup.mode == .off ? "off" : "\(settings.cleanup.mode.rawValue)\(amount(settings.cleanup.amount))"
        let voice = settings.voice.preset == .off ? "off" : "\(settings.voice.preset.rawValue)\(amount(settings.voice.amount))"
        return "\(source)-\(cleanup)-\(voice).wav"
    }
}

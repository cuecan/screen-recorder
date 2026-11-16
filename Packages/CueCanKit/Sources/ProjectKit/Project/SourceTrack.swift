import Foundation

/// One file of a source: a screen, a camera, a mic, system audio, or an imported video.
public struct SourceTrack: Codable, Equatable, Sendable {
    /// What a track holds.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A screen capture (video only).
        case screen
        /// A camera recorded by the app (video only; its sound comes from the mic track).
        case camera
        /// An imported video file, usually with its own audio.
        case video
        /// A mic recorded by the app: raw, uncompressed.
        case microphone
        /// The Mac's system audio recorded by the app.
        case systemAudio
        /// An imported audio file, such as a separate mic recording.
        case audio

        /// Whether a take is only as long as this track: its pictures and its voice. System audio isn't
        /// one, since where it has nothing there's silence, which is what it would have recorded.
        public var setsLength: Bool { self != .systemAudio }
    }

    public var kind: Kind
    /// Where the file is (``FileReference``).
    public var file: FileReference
    /// When this track starts, in seconds of source time. A recording's tracks are cut to the time they
    /// all cover when the take is saved (docs/decisions.md, 87), so this is zero, but for system audio
    /// that began late, and for a take whose files couldn't be cut.
    public var startOffset: TimeInterval
    public var media: MediaInfo

    public init(kind: Kind, file: FileReference, startOffset: TimeInterval = 0, media: MediaInfo) {
        self.kind = kind
        self.file = file
        self.startOffset = startOffset
        self.media = media
    }
}

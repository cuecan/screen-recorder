import Foundation

/// One recording or one imported file, with all the tracks that share its clock.
///
/// A screen recording is one source whose tracks are the screen, the camera, the mic and system audio,
/// each its own file, lined up by their host-clock start times. An imported phone clip is one source with
/// a single video track that carries its own audio. A separate mic recording, or a second camera, is a
/// source of its own, lined up with another by ``sync``.
///
/// Source time zero is the earliest start among the source's tracks. Clips and transcripts are in
/// source time.
public struct Source: Codable, Equatable, Sendable, Identifiable {
    /// Where a source came from.
    public enum Origin: String, Codable, Sendable {
        /// Recorded by the app: its files are in the project's `recordings/` folder.
        case recorded
        /// Imported from elsewhere on disk, and referenced where it is.
        case imported
    }

    public let id: SourceID
    /// A name for people, such as "Screen recording 10:42" or "IMG_2231.MOV".
    public var name: String
    public var origin: Origin
    public var tracks: [SourceTrack]
    /// How this source lines up with another one. Nil for a source that is its own reference.
    public var sync: SourceSync?
    /// The preset area, for a screen recording of an area of the display.
    public var captureArea: CaptureArea?
    /// The layout the take was set up with, which its shape comes from (docs/decisions.md, 89). Nil
    /// for a take of the camera alone. A clip's ``Layout/automatic`` is this.
    public var layout: TakeLayout?
    /// The transcript's file name in `transcripts/`, once the source is transcribed.
    public var transcriptFile: String?
    /// The screen log's name in `screen/`, for a recording made with a screen (``ScreenLog``).
    public var screenLog: String?
    /// How far the camera's picture was moved earlier to meet the voice when the take was saved, in seconds:
    /// the delay measured for its camera and mic (docs/decisions.md, 83 and 88). It's cut into the camera's
    /// file, so nothing applies it again; it's kept to show what the take was saved with. Nil for a take
    /// without both a camera and sound.
    public var lipSync: TimeInterval?

    public init(
        id: SourceID,
        name: String,
        origin: Origin,
        tracks: [SourceTrack],
        sync: SourceSync? = nil,
        captureArea: CaptureArea? = nil,
        layout: TakeLayout? = nil,
        transcriptFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.origin = origin
        self.tracks = tracks
        self.sync = sync
        self.captureArea = captureArea
        self.layout = layout
        self.transcriptFile = transcriptFile
    }

    /// The source's length: from source time zero to where its shortest picture or voice track ends, so
    /// nothing in it is missing a picture or the voice (docs/decisions.md, 87). A recording's tracks are cut
    /// to end together. With only system audio, that track's end.
    public var duration: TimeInterval {
        let ends = tracks.filter(\.kind.setsLength).map { $0.startOffset + $0.media.duration }
        return ends.min() ?? tracks.map { $0.startOffset + $0.media.duration }.max() ?? 0
    }

    /// The first track of a kind, if the source has one.
    public func track(_ kind: SourceTrack.Kind) -> SourceTrack? {
        tracks.first { $0.kind == kind }
    }

    /// The track to transcribe and to hear by default: the dedicated mic if there is one, otherwise the
    /// audio of the video, otherwise any audio.
    public var primaryAudioTrack: SourceTrack? {
        track(.microphone)
            ?? tracks.first { $0.kind == .video && $0.media.audio != nil }
            ?? track(.audio)
    }
}

import Foundation

/// `edit.json`: the cut, as a timeline of clips over the project's sources.
///
/// The main track is the person talking, in playback order. Overlays sit over ranges of the main track's
/// words, or of its source time, so they follow every cut, and so do freezes. The look, fixes to the transcript, audio
/// and camera framing are settings for the whole edit. Every change
/// goes through ``ProjectFolder/updateEdit(author:reason:_:)``, which snapshots the previous version into
/// `history/` first.
public struct Edit: Codable, Equatable, Sendable {
    /// The format version of `edit.json`. Bump it on any incompatible change.
    public static let currentFormatVersion = 11

    public var formatVersion: Int
    /// Goes up by one on every saved change. The app watches it to know when to rebuild the preview.
    public var revision: Int
    /// The next number for a clip id (`c_<n>`).
    public var nextClipNumber: Int
    /// The main track, in playback order.
    public var main: [Clip]
    /// Pictures and clips on top of the main track, back to front (docs/decisions.md, 54).
    public var overlays: [Overlay]
    /// Where the picture holds on one frame (docs/decisions.md, 59).
    public var freezes: [Freeze]
    /// Fixes to the transcript, laid over it in order: each replaces a run of words (docs/decisions.md, 69).
    public var fixes: [WordFix]
    /// What every clip shares, in both shapes: rounded corners, the background and mirroring. Each clip sets
    /// its own inset and camera side (docs/decisions.md, 61, 68 and 77).
    public var look: EditLook
    public var audio: AudioSettings
    /// Animated captions (docs/decisions.md, 80).
    public var captions: Captions
    /// How each source's camera is framed, by source and by kind of slot. A source without an entry is
    /// centred, not zoomed (docs/decisions.md, 52).
    public var camera: [SourceID: CameraFramings]

    public init(
        main: [Clip] = [],
        overlays: [Overlay] = [],
        freezes: [Freeze] = [],
        fixes: [WordFix] = [],
        look: EditLook = EditLook(),
        audio: AudioSettings = AudioSettings(),
        captions: Captions = Captions(),
        camera: [SourceID: CameraFramings] = [:]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.revision = 0
        self.nextClipNumber = 1
        self.main = main
        self.overlays = overlays
        self.freezes = freezes
        self.fixes = fixes
        self.look = look
        self.audio = audio
        self.captions = captions
        self.camera = camera
        self.nextClipNumber = highestNumber + 1
    }

    /// The look a clip is drawn with, in either shape: its own camera side over what the edit shares.
    public func look(of clip: Clip) -> OutputLook {
        OutputLook(look, clip.look)
    }

    /// The whole look as most of the edit plays it: what the edit shares, with the camera side that covers
    /// the most time, for the next take to start with. Nil with no clips.
    public var prevailingLook: OutputLook? {
        guard !main.isEmpty else { return nil }
        // Captions don't carry into the next take: they're turned on per edit (docs/decisions.md, 80).
        let looks = main.map { var look = $0.look; look.captions = false; return look }
        var time: [ClipLook: TimeInterval] = [:]
        for (clip, look) in zip(main, looks) { time[look, default: 0] += clip.duration }
        // Ties go to the earliest clip's look, so the answer doesn't depend on dictionary order.
        let most = time.values.max() ?? 0
        return OutputLook(look, looks.first { time[$0] == most } ?? ClipLook())
    }

    /// How a source's camera is framed, slot by slot.
    public func framings(for source: SourceID) -> CameraFramings {
        camera[source] ?? CameraFramings()
    }

    /// Frames one kind of slot of a source's camera, leaving the others as they are.
    public mutating func setFraming(_ framing: CameraFraming, slot: CameraSlot, for source: SourceID) {
        var framings = framings(for: source)
        framings[slot] = framing
        camera[source] = framings
    }

    /// Replaces how a source's camera is framed. No framed slot is stored as no entry.
    public mutating func setFramings(_ framings: CameraFramings, for source: SourceID) {
        camera[source] = framings.isEmpty ? nil : framings
    }

    /// The highest number any clip, overlay or freeze id uses. They share one counter.
    private var highestNumber: Int {
        max(main.map(\.id.number).max() ?? 0, overlays.map(\.id.number).max() ?? 0, freezes.map(\.id.number).max() ?? 0)
    }

    /// Takes the next number for a clip, overlay or freeze id.
    private mutating func makeNumber() -> Int {
        nextClipNumber = max(nextClipNumber, highestNumber + 1)
        defer { nextClipNumber += 1 }
        return nextClipNumber
    }

    /// Takes the next clip id, for a clip or an overlay.
    public mutating func makeClipID() -> ClipID {
        ClipID(number: makeNumber())
    }

    /// Takes the next freeze id.
    public mutating func makeFreezeID() -> FreezeID {
        FreezeID(number: makeNumber())
    }

    /// The edit's length: the main track's clips back to back.
    public var duration: TimeInterval {
        main.reduce(0) { $0 + $1.duration }
    }

    /// Where each main-track clip starts on the edited timeline.
    public var clipStartTimes: [TimeInterval] {
        var position: TimeInterval = 0
        return main.map { clip in
            defer { position += clip.duration }
            return position
        }
    }
}

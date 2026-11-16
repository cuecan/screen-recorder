import Foundation

/// A range of one source on the main track.
///
/// For a screen recording, the clip carries the screen, the camera and the mic together, because they
/// share a clock. Its edges are plain source times (docs/decisions.md, 56). Cutting by word id snaps them
/// to real silences (``CutPointSnapper``), and the creator or Claude can then put an edge at any time.
/// A nudge is kept as an offset from where the edge was put, so that place stays visible and the nudge
/// can be undone or changed on its own.
public struct Clip: Codable, Equatable, Sendable, Identifiable {
    public let id: ClipID
    public var source: SourceID
    /// Where the edges were put, by a cut or by hand, in seconds of source time.
    public var sourceIn: TimeInterval
    public var sourceOut: TimeInterval
    /// How far the start and end have been nudged from where they were put, in seconds. Positive is later.
    public var startNudge: TimeInterval
    public var endNudge: TimeInterval
    /// Whether this clip starts where a split divided a clip. It plays on from the clip before it, and is
    /// never joined back to it, so the two can have different layouts.
    public var startsAtSplit: Bool
    /// Whether the creator placed an edge by hand. Claude's broad passes, such as `remove_silences`, leave
    /// these edges alone (docs/decisions.md, 56).
    public var startPlacedByHand: Bool
    public var endPlacedByHand: Bool
    /// Which audio to hear. Nil means the source's own primary audio (``Source/primaryAudioTrack``).
    public var audio: ClipAudio?
    /// Whether the clip plays silently: no voice and no system audio.
    public var isMuted: Bool
    /// The voice's level in the mix, in dB (``SoundLevel``): the mic the clip plays (docs/decisions.md, 71).
    public var voiceLevel: Double { didSet { voiceLevel = SoundLevel.clamped(voiceLevel) } }
    /// System audio's level in the mix, in dB.
    public var systemAudioLevel: Double { didSet { systemAudioLevel = SoundLevel.clamped(systemAudioLevel) } }
    /// How fast the clip plays (docs/decisions.md, 59).
    public var speed: ClipSpeed
    /// The clip's layout, drawn for whichever shape is shown or exported: one layout, never one for the
    /// video and another for the Short (docs/decisions.md, 77).
    public var layout: Layout
    /// The clip's camera side and captions, the same in both shapes (docs/decisions.md, 68 and 77).
    public var look: ClipLook
    /// A static enlargement and centre for this clip's screen. Nil shows the entire recorded area.
    public var screenTransform: PictureTransform?
    /// A static framing of this clip's camera. Nil follows the take's framing for its layout's slot.
    public var cameraTransform: PictureTransform?

    public init(
        id: ClipID,
        source: SourceID,
        sourceIn: TimeInterval,
        sourceOut: TimeInterval,
        startNudge: TimeInterval = 0,
        endNudge: TimeInterval = 0,
        startsAtSplit: Bool = false,
        startPlacedByHand: Bool = false,
        endPlacedByHand: Bool = false,
        audio: ClipAudio? = nil,
        isMuted: Bool = false,
        voiceLevel: Double = 0,
        systemAudioLevel: Double = 0,
        speed: ClipSpeed = .normal,
        layout: Layout = .automatic,
        look: ClipLook = ClipLook(),
        screenTransform: PictureTransform? = nil,
        cameraTransform: PictureTransform? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.startNudge = startNudge
        self.endNudge = endNudge
        self.startsAtSplit = startsAtSplit
        self.startPlacedByHand = startPlacedByHand
        self.endPlacedByHand = endPlacedByHand
        self.audio = audio
        self.isMuted = isMuted
        self.voiceLevel = SoundLevel.clamped(voiceLevel)
        self.systemAudioLevel = SoundLevel.clamped(systemAudioLevel)
        self.speed = speed
        self.layout = layout
        self.look = look
        self.screenTransform = screenTransform
        self.cameraTransform = cameraTransform
    }

    /// How long the clip plays on the edited timeline, nudges and speed included.
    public var duration: TimeInterval { playedRange.duration / speed.rate }

    /// The range of source time between where the edges were put, before nudges.
    public var sourceRange: TimeRange { TimeRange(start: sourceIn, end: sourceOut) }

    /// The range of source time the clip plays: where the edges were put, nudged.
    public var playedRange: TimeRange { TimeRange(start: sourceIn + startNudge, end: sourceOut + endNudge) }

    /// The source time playing a given time into the clip on the edited timeline.
    public func sourceTime(atOffset offset: TimeInterval) -> TimeInterval {
        playedRange.start + offset * speed.rate
    }

    /// How far into the clip, on the edited timeline, a moment of its source plays.
    public func offset(ofSourceTime time: TimeInterval) -> TimeInterval {
        (time - playedRange.start) / speed.rate
    }

    /// Whether an edge was placed by hand.
    public func isPlacedByHand(_ edge: ClipEdge) -> Bool {
        edge == .start ? startPlacedByHand : endPlacedByHand
    }

    /// Whether two clips look and sound the same, so they can be joined into one when they meet.
    func hasSamePresentation(as other: Clip) -> Bool {
        source == other.source && audio == other.audio && layout == other.layout
            && look == other.look && isMuted == other.isMuted && speed == other.speed
            && voiceLevel == other.voiceLevel && systemAudioLevel == other.systemAudioLevel
            && screenTransform == other.screenTransform && cameraTransform == other.cameraTransform
    }

    // Anything beyond the plain clip is only written when set, so a plain clip reads as before.
    private enum CodingKeys: String, CodingKey {
        case id, source, sourceIn, sourceOut, startNudge, endNudge, startsAtSplit, startPlacedByHand, endPlacedByHand
        case audio, muted, voiceLevel, systemAudioLevel, speed, layout, look, screenTransform, cameraTransform
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ClipID.self, forKey: .id)
        source = try container.decode(SourceID.self, forKey: .source)
        sourceIn = try container.decode(TimeInterval.self, forKey: .sourceIn)
        sourceOut = try container.decode(TimeInterval.self, forKey: .sourceOut)
        startNudge = try container.decodeIfPresent(TimeInterval.self, forKey: .startNudge) ?? 0
        endNudge = try container.decodeIfPresent(TimeInterval.self, forKey: .endNudge) ?? 0
        startsAtSplit = try container.decodeIfPresent(Bool.self, forKey: .startsAtSplit) ?? false
        startPlacedByHand = try container.decodeIfPresent(Bool.self, forKey: .startPlacedByHand) ?? false
        endPlacedByHand = try container.decodeIfPresent(Bool.self, forKey: .endPlacedByHand) ?? false
        audio = try container.decodeIfPresent(ClipAudio.self, forKey: .audio)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        voiceLevel = SoundLevel.clamped(try container.decodeIfPresent(Double.self, forKey: .voiceLevel) ?? 0)
        systemAudioLevel = SoundLevel.clamped(try container.decodeIfPresent(Double.self, forKey: .systemAudioLevel) ?? 0)
        speed = try container.decodeIfPresent(ClipSpeed.self, forKey: .speed) ?? .normal
        layout = try container.decode(Layout.self, forKey: .layout)
        look = try container.decode(ClipLook.self, forKey: .look)
        screenTransform = try container.decodeIfPresent(PictureTransform.self, forKey: .screenTransform)
        cameraTransform = try container.decodeIfPresent(PictureTransform.self, forKey: .cameraTransform)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(sourceIn, forKey: .sourceIn)
        try container.encode(sourceOut, forKey: .sourceOut)
        if startNudge != 0 { try container.encode(startNudge, forKey: .startNudge) }
        if endNudge != 0 { try container.encode(endNudge, forKey: .endNudge) }
        if startsAtSplit { try container.encode(true, forKey: .startsAtSplit) }
        if startPlacedByHand { try container.encode(true, forKey: .startPlacedByHand) }
        if endPlacedByHand { try container.encode(true, forKey: .endPlacedByHand) }
        try container.encodeIfPresent(audio, forKey: .audio)
        if isMuted { try container.encode(true, forKey: .muted) }
        if voiceLevel != 0 { try container.encode(voiceLevel, forKey: .voiceLevel) }
        if systemAudioLevel != 0 { try container.encode(systemAudioLevel, forKey: .systemAudioLevel) }
        if speed != .normal { try container.encode(speed, forKey: .speed) }
        try container.encode(layout, forKey: .layout)
        try container.encode(look, forKey: .look)
        try container.encodeIfPresent(screenTransform, forKey: .screenTransform)
        try container.encodeIfPresent(cameraTransform, forKey: .cameraTransform)
    }
}

import Foundation
import ProjectKit
import RenderKit

/// The edit as Claude reads it back: each clip with the words it plays, where it lands, its layouts, speed and
/// hand-placed edges and sound levels; the overlays with theirs, the freezes and the look.
struct EditSummary: Encodable {
    struct ClipSummary: Encodable {
        var id: ClipID
        var source: SourceID
        /// The first and last transcript items the clip plays.
        var from: TranscriptItemID?
        var to: TranscriptItemID?
        /// The words it plays, shortened in the middle when long.
        var text: String
        var timelineStart: Double
        var duration: Double
        /// The clip's one layout, drawn for whichever shape is shown or exported.
        var layout: Layout
        /// The clip's camera side and captions, the same in both shapes.
        var look: ClipLook
        var startNudgeMilliseconds: Int?
        var endNudgeMilliseconds: Int?
        var startsAtSplit: Bool?
        /// The source time the clip plays, so a cut by time can name it.
        var sourceStart: Double
        var sourceEnd: Double
        /// Edges the creator placed by hand: broad passes such as remove_silences leave them alone.
        var placedByHand: [ClipEdge]?
        var speed: String?
        /// The voice's and system audio's levels in the mix, in dB (docs/decisions.md, 71). 0 is as recorded.
        var voiceDb: Double
        var systemAudioDb: Double
        var muted: Bool?
        var audio: ClipAudio?
        var screenTransform: PictureTransform?
        var cameraTransform: PictureTransform?
        /// Edges that sound runs right across, measured against the recording's silence level
        /// (docs/decisions.md, 75): they may catch a word.
        var soundAtEdges: [EdgeSoundSummary]?
    }

    struct EdgeSoundSummary: Encodable {
        var edge: ClipEdge
        var sourceTime: Double
        var dbOverSilence: Double
        /// How long the sound runs before and after the edge, in seconds of source time, up to 2.
        var soundBefore: Double
        var soundAfter: Double
        /// nudge_cut milliseconds that move the edge clear of the sound: outward to keep it whole, inward to leave it out.
        var nudgeToKeepIt: Int?
        var nudgeToLeaveItOut: Int?
        /// nudge_cut milliseconds to the nearest dip between words or syllables, earlier and later: the smaller move.
        var nudgeToDipEarlier: Int?
        var nudgeToDipLater: Int?
    }

    struct OverlaySummary: Encodable {
        var id: ClipID
        var shows: String
        var placement: Overlay.Placement
        /// The words or the source time it sits over.
        var over: String
        var muted: Bool?
        /// A video's own sound level in the mix, in dB.
        var levelDb: Double?
        /// Where it shows on the timeline; nil when none of what it sits over is played.
        var timelineStart: Double?
        var duration: Double?
    }

    struct FreezeSummary: Encodable {
        var id: FreezeID
        var source: SourceID
        var sourceStart: Double
        var sourceEnd: Double
        var holdsFrameAt: Double
        /// Where it shows on the timeline.
        var timeline: [[Double]]
    }

    struct Change: Encodable {
        var number: Int
        var author: EditAuthor
        var reason: String
        var savedAt: Date
    }

    var revision: Int
    var duration: Double
    var format: String
    var outputs: [OutputShape]
    /// What every clip shares, in both shapes, the inset included; each clip has its own camera side.
    var look: EditLook
    /// Animated captions (docs/decisions.md, 80), when any are on or any words are emphasised or break a line.
    var captions: Captions?
    /// How each source's camera is framed, by kind of slot, for the sources with a framed slot. A slot not
    /// listed is centred, except fullScreen, which follows Side by side's.
    var camera: [SourceID: CameraFramings]?
    var clips: [ClipSummary]
    var overlays: [OverlaySummary]
    var freezes: [FreezeSummary]
    /// The latest changes, newest last. Undo to before one with `undo` and its number.
    var changes: [Change]?

    init(edit: Edit, project: Project, transcripts: TranscriptIndex, history: [EditHistory.Entry]? = nil, edgeSounds: [EdgeSound]? = nil) {
        let timeline = EditTimeline(edit: edit, transcripts: transcripts)
        revision = edit.revision
        duration = Self.rounded(edit.duration)
        format = project.effectiveFormat.label
        outputs = project.effectiveFormat.outputs
        look = edit.look
        captions = edit.showsCaptions || !edit.captions.emphasis.isEmpty || !edit.captions.lineBreaks.isEmpty ? edit.captions : nil
        camera = edit.camera.isEmpty ? nil : edit.camera
        clips = timeline.clips.map { placed in
            let clip = placed.clip
            let items = transcripts[clip.source].map { Self.items(of: $0, in: clip.playedRange) } ?? []
            let words = items.compactMap { item -> String? in if case .word(let word) = item { word.text } else { nil } }
            return ClipSummary(
                id: clip.id,
                source: clip.source,
                from: items.first?.id,
                to: items.last?.id,
                text: Self.shortened(words),
                timelineStart: Self.rounded(placed.timeline.start),
                duration: Self.rounded(placed.timeline.duration),
                layout: clip.layout,
                look: clip.look,
                startNudgeMilliseconds: clip.startNudge == 0 ? nil : Int((clip.startNudge * 1000).rounded()),
                endNudgeMilliseconds: clip.endNudge == 0 ? nil : Int((clip.endNudge * 1000).rounded()),
                startsAtSplit: clip.startsAtSplit ? true : nil,
                sourceStart: Self.rounded(clip.playedRange.start),
                sourceEnd: Self.rounded(clip.playedRange.end),
                placedByHand: clip.startPlacedByHand || clip.endPlacedByHand
                    ? ClipEdge.allCases.filter { clip.isPlacedByHand($0) } : nil,
                speed: clip.speed.isNormal ? nil : "\(clip.speed.label) \(clip.speed.sound == .muted ? "muted" : "pitch kept")",
                voiceDb: Self.rounded(clip.voiceLevel),
                systemAudioDb: Self.rounded(clip.systemAudioLevel),
                muted: clip.isMuted ? true : nil,
                audio: clip.audio,
                screenTransform: clip.screenTransform,
                cameraTransform: clip.cameraTransform,
                soundAtEdges: Self.edgeSounds(edgeSounds, of: clip.id)
            )
        }
        overlays = edit.overlays.map { item in
            let pieces = timeline.overlays.filter { $0.overlay.id == item.id }
            let over: String = switch item.over {
            case .words(let range): range.description
            case .time(let source, let range): "\(source) \(Self.rounded(range.start))–\(Self.rounded(range.end)) s"
            }
            let shows: String = switch item.media {
            case .source(let id): "source \(id)"
            case .file(let file, let still): "\(still ? "picture" : "video") \(file.path)"
            }
            return OverlaySummary(
                id: item.id,
                shows: shows,
                placement: item.placement,
                over: over,
                muted: item.isStill ? nil : item.isMuted,
                levelDb: item.isStill ? nil : Self.rounded(item.level),
                timelineStart: pieces.first.map { Self.rounded($0.timeline.start) },
                duration: pieces.isEmpty ? nil : Self.rounded(pieces.map(\.timeline.duration).reduce(0, +))
            )
        }
        freezes = edit.freezes.map { freeze in
            FreezeSummary(
                id: freeze.id,
                source: freeze.source,
                sourceStart: Self.rounded(freeze.range.start),
                sourceEnd: Self.rounded(freeze.range.end),
                holdsFrameAt: Self.rounded(freeze.frame),
                timeline: edit.timelinePieces(of: freeze.range, in: freeze.source).map { [Self.rounded($0.timeline.start), Self.rounded($0.timeline.end)] }
            )
        }
        changes = history.map { entries in
            entries.suffix(20).map { Change(number: $0.sequence, author: $0.author, reason: $0.reason, savedAt: $0.savedAt) }
        }
    }

    /// The items whose middle a stretch of source time plays.
    static func items(of transcript: Transcript, in range: TimeRange) -> [TranscriptItem] {
        transcript.items.filter { item in
            let middle = (item.start + item.end) / 2
            return middle >= range.start && middle < range.end
        }
    }

    static func shortened(_ words: [String], keeping: Int = 8) -> String {
        guard words.count > keeping * 2 else { return words.joined(separator: " ") }
        return words.prefix(keeping).joined(separator: " ") + " … " + words.suffix(keeping).joined(separator: " ")
    }

    private static func edgeSounds(_ sounds: [EdgeSound]?, of clip: ClipID) -> [EdgeSoundSummary]? {
        let mine = (sounds ?? []).filter { $0.clip == clip }
        guard !mine.isEmpty else { return nil }
        return mine.map { sound in
            let outward = sound.edge == .start ? -1.0 : 1.0
            func nudge(_ seconds: TimeInterval) -> Int? {
                abs(seconds) >= EdgeSound.reach - 0.005 ? nil : Int((seconds * 1000).rounded())
            }
            return EdgeSoundSummary(edge: sound.edge, sourceTime: rounded(sound.sourceTime), dbOverSilence: sound.overSilence.rounded(),
                                    soundBefore: rounded(sound.soundBefore), soundAfter: rounded(sound.soundAfter),
                                    nudgeToKeepIt: nudge(outward * sound.toKeepIt), nudgeToLeaveItOut: nudge(-outward * sound.toLeaveItOut),
                                    nudgeToDipEarlier: sound.dipBefore.map { Int((-$0 * 1000).rounded()) },
                                    nudgeToDipLater: sound.dipAfter.map { Int(($0 * 1000).rounded()) })
        }
    }

    static func rounded(_ seconds: Double) -> Double {
        (seconds * 1000).rounded() / 1000
    }
}

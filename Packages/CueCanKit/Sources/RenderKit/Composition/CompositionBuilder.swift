import AVFoundation
import CoreImage
import Foundation
import ProjectKit

/// Turns `edit.json` into an `AVComposition`: the one function the preview, the stills and the export all
/// use, so what plays is exactly what exports (docs/decisions.md, 13).
///
/// - Each kind of picture (screen, camera, imported video) has its own lane of video, and each overlay its
///   own. ``LayoutCompositor`` places them per frame, in each clip's look (61 and 77).
/// - The voice is a lane of its own: the cleaned voice from `audio/` when one matches the source's current
///   settings, otherwise the raw mic. System audio is a second lane, and each overlay with sound its own.
///   Each lane plays at its level (the Sound tab), and a muted clip plays no sound.
/// - A sped-up clip's time is scaled, its sound kept at pitch or muted. A freeze stretches one frame of the
///   picture over its range while the camera and the voice play on (59).
/// - Cuts are exact to the sample. The picture changes on the frame nearest the cut, so picture and sound
///   edges can differ by up to a frame.
/// - Each join gets a short fade, so a cut never clicks. A split plays straight through.
/// - Several outputs can be built into one composition, side by side at one height, so the editor previews
///   the video and the Short from one player and one playhead (54).
public enum CompositionBuilder {
    /// How long the fade out and back in at each join lasts. A starting value: long enough to stop a click,
    /// too short to hear as a dip (TEST NEEDED by ear).
    public static let joinFade: TimeInterval = 0.004
    /// Times are kept to the sample at 48 kHz.
    static let timescale: CMTimeScale = 48_000
    /// How a sped-up clip keeps its pitch. Spectral is AVFoundation's highest-quality pitch-kept algorithm
    /// (VERIFY by ear where speech stops sounding right: docs/decisions.md, 59).
    public static let pitchAlgorithm = AVAudioTimePitchAlgorithm.spectral

    /// Builds the composition for one output shape.
    ///
    /// - Parameter scale: 1 for 1080p, 2 for 4K.
    public static func build(_ inputs: RenderInputs, output: OutputShape, scale: Double = 1) async throws -> BuiltComposition {
        try await build(inputs, outputs: [output], scale: scale)
    }

    /// Builds one composition showing several outputs side by side, all as tall as the shortest at `scale`:
    /// at 1 that's the 1920 × 1080 video beside a 608 × 1080 Short.
    public static func build(_ inputs: RenderInputs, outputs: [OutputShape], scale: Double = 1) async throws -> BuiltComposition {
        let outputs = outputs.isEmpty ? [.landscape] : outputs
        let edit = inputs.edit
        let timeline = EditTimeline(edit: edit, transcripts: inputs.transcripts)
        guard !timeline.clips.isEmpty, timeline.duration > 0 else { throw RenderError.emptyEdit }

        let composition = AVMutableComposition()
        var lanes = Lanes(composition: composition, folder: inputs.folder.url)
        let clock = SourceClock(project: inputs.project)

        // Main track.
        // Each clip's stretch of the timeline, whether it plays straight on into the next, and its levels.
        var voiceSegments: [(range: TimeRange, playsOn: Bool, voice: Float, system: Float)] = []
        for (index, placed) in timeline.clips.enumerated() {
            try Task.checkCancellation()
            let clip = placed.clip
            guard let source = inputs.project.source(clip.source) else { throw EditError.unknownSource(clip.source) }
            let played = clip.playedRange
            let rate = clip.speed.rate
            // With no screen, the camera is the picture, so the camera holds (docs/decisions.md, 59).
            let held = [SourceTrack.Kind.screen, .camera, .video].first { source.track($0)?.media.video != nil }
            for kind in [SourceTrack.Kind.screen, .camera, .video] {
                guard let track = source.track(kind), track.media.video != nil else { continue }
                let pieces = kind == held ? Self.pieces(of: played, holds: edit.freezes.filter { $0.source == source.id }) : [(played, nil)]
                for (range, frame) in pieces {
                    let at = placed.timelineTime(ofSourceTime: range.start)
                    if let frame {
                        try await lanes.insertFrame(track, lane: Lanes.Key(kind), sourceTime: frame, at: at, lasting: range.duration / rate)
                    } else {
                        try await lanes.insert(track, mediaType: .video, lane: Lanes.Key(kind), sourceRange: range, at: at, rate: rate)
                    }
                }
            }
            let silent = clip.isMuted || clip.speed.sound == .muted
            if !silent, let (audioSource, track) = audio(for: clip, source: source, project: inputs.project),
                let start = clock.time(played.start, in: source.id, as: audioSource.id)
            {
                let cleaned = audioSource.primaryAudioTrack == track
                    ? inputs.primaryAudio[audioSource.id]
                    : nil
                try await lanes.insert(
                    track,
                    file: cleaned,
                    mediaType: .audio,
                    lane: .voice,
                    sourceRange: TimeRange(start: start, end: start + played.duration),
                    at: placed.timeline.start,
                    rate: rate
                )
            }
            if !silent, clip.audio == nil, let system = source.track(.systemAudio) {
                try await lanes.insert(system, mediaType: .audio, lane: .system, sourceRange: played, at: placed.timeline.start, rate: rate)
            }
            let next = index + 1 < timeline.clips.count ? timeline.clips[index + 1].clip : nil
            voiceSegments.append((placed.timeline, next?.startsAtSplit == true,
                                  Float(SoundLevel.volume(forGain: clip.voiceLevel)), Float(SoundLevel.volume(forGain: clip.systemAudioLevel))))
        }

        // Overlays, each on its own lane so overlapping ones don't collide.
        var overlayPictures: [Int: (size: CGSize, still: String?)] = [:]
        var stills: [String: CIImage] = [:]
        for (index, placed) in timeline.overlays.enumerated() {
            try Task.checkCancellation()
            let overlay = placed.overlay
            let mediaRange = TimeRange(start: placed.mediaStart, end: placed.mediaStart + placed.timeline.duration)
            switch overlay.media {
            case .source(let id):
                guard let source = inputs.project.source(id) else { throw EditError.unknownSource(id) }
                guard let track = source.track(.video) ?? source.track(.camera) ?? source.track(.screen), let video = track.media.video else { continue }
                try await lanes.insert(track, mediaType: .video, lane: .overlay(index), sourceRange: mediaRange, at: placed.timeline.start)
                overlayPictures[index] = (CGSize(width: video.width, height: video.height), nil)
                if overlay.playsSound, let sound = source.primaryAudioTrack {
                    try await lanes.insert(sound, mediaType: .audio, lane: .overlayAudio(index), sourceRange: mediaRange, at: placed.timeline.start)
                }
            case .file(let file, let isStill):
                let url = file.url(relativeTo: inputs.folder.url)
                if isStill {
                    let key = url.path(percentEncoded: false)
                    if stills[key] == nil {
                        guard FileManager.default.fileExists(atPath: key) else { throw RenderError.missingFile(url) }
                        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                            throw RenderError.unreadableFile(url, "It isn't a picture CueCan can read.")
                        }
                        stills[key] = image
                    }
                    overlayPictures[index] = (stills[key]?.extent.size ?? .zero, key)
                } else {
                    let track = SourceTrack(kind: .video, file: file, media: MediaInfo(duration: 0))
                    try await lanes.insert(track, mediaType: .video, lane: .overlay(index), sourceRange: mediaRange, at: placed.timeline.start)
                    guard let size = try await lanes.naturalSize(of: url) else { continue }
                    overlayPictures[index] = (size, nil)
                    if overlay.playsSound {
                        try await lanes.insert(track, mediaType: .audio, lane: .overlayAudio(index), sourceRange: mediaRange, at: placed.timeline.start)
                    }
                }
            }
        }

        // The outputs side by side, as tall as the shortest.
        let height = outputs.map { Double($0.height) * scale }.min() ?? Double(OutputShape.landscape.height) * scale
        var panels: [(output: OutputShape, rect: CGRect, scale: Double)] = []
        var x = 0.0
        for output in outputs {
            let panelScale = height / Double(output.height)
            let width = Double(output.width) * panelScale
            panels.append((output, CGRect(x: x, y: 0, width: width, height: height), panelScale))
            x += width
        }
        let renderSize = CGSize(width: (x / 2).rounded(.up) * 2, height: (height / 2).rounded(.up) * 2)

        // Captions, once for each output that has them: the pages are the same on every stretch.
        var captionTracks: [OutputShape: CaptionTrack] = [:]
        for panel in panels where captionTracks[panel.output] == nil {
            captionTracks[panel.output] = CaptionTrack.make(inputs, timeline: timeline, output: panel.output)
        }

        // The pictures, stretch by stretch.
        var instructions: [LayoutInstruction] = []
        for segment in timeline.segments {
            let clip = timeline.clips[segment.clipIndex].clip
            guard let source = inputs.project.source(clip.source) else { continue }
            let pictures = ClipPictures(source: source, cameraFramings: edit.framings(for: source.id))
            var drawn: [LayoutInstruction.Panel] = []
            for panel in panels {
                let look = edit.look(of: clip)
                let frame = LayoutGeometry.frame(for: clip.layout, in: panel.output, pictures: pictures, scale: panel.scale, look: look,
                                                 screenTransform: clip.screenTransform, cameraTransform: clip.cameraTransform)
                var items: [(item: LayoutInstruction.Item, isScreen: Bool)] = frame.placements.compactMap { placement in
                    lanes.trackID(Lanes.Key(placement.role)).map { (.track(placement, $0), placement.role == .screen) }
                }
                for overlayIndex in segment.overlayIndices {
                    guard let picture = overlayPictures[overlayIndex] else { continue }
                    let overlay = timeline.overlays[overlayIndex].overlay
                    let screen = items.firstIndex { $0.isScreen }
                    let inScreen = overlay.placement == .inScreensPlace ? screen : nil
                    let slot: CGRect
                    var corners = Corners.square
                    if inScreen != nil, let screenPlacement = frame.placement(.screen) {
                        slot = screenPlacement.frame
                        corners = screenPlacement.corners
                    } else {
                        slot = CGRect(origin: .zero, size: frame.size)
                    }
                    let placement = LayoutGeometry.overlay(size: picture.size, into: slot, isStill: picture.still != nil, corners: corners)
                    let item: LayoutInstruction.Item
                    if let key = picture.still {
                        item = .image(placement, key)
                    } else if let trackID = lanes.trackID(.overlay(overlayIndex)) {
                        item = .track(placement, trackID)
                    } else {
                        continue
                    }
                    if let inScreen {
                        // Replacing its contents doesn't remove the screen slot. Later overlays target
                        // the original tile, even if a still inside it has a different aspect ratio.
                        items[inScreen] = (item, true)
                    } else {
                        // Covering the frame hides everything under it.
                        items = [(item, false)]
                    }
                }
                drawn.append(LayoutInstruction.Panel(rect: panel.rect, background: look.backgroundComponents, backdrop: look.backdrop, addOns: look.addOns,
                                                     items: items.map(\.item),
                                                     captions: clip.look.captions
                                                        ? captionTracks[panel.output].map { PanelCaptions.make(track: $0, frame: frame) } : nil))
            }
            instructions.append(LayoutInstruction(timeRange: cmRange(segment.timeline), panels: drawn, renderSize: renderSize, stills: stills))
        }
        guard instructions.contains(where: { $0.panels.contains { !$0.items.isEmpty } }) else { throw RenderError.noPicture }
        // Instructions must meet end to end, so each starts exactly where the one before ends.
        instructions = joined(instructions)

        let videoComposition = AVVideoComposition(
            configuration: AVVideoComposition.Configuration(
                customVideoCompositorClass: LayoutCompositor.self,
                frameDuration: CMTime(value: 1, timescale: CMTimeScale(frameRate(inputs.project, timeline: timeline))),
                instructions: instructions,
                renderSize: renderSize
            )
        )

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = lanes.audioLanes.map { key, lane in
            let parameters = AVMutableAudioMixInputParameters(track: lane)
            parameters.audioTimePitchAlgorithm = pitchAlgorithm
            switch key {
            case .voice, .system:
                // Each clip at its own level (docs/decisions.md, 71). Across a split's join the level steps
                // from one clip's to the next's.
                for segment in voiceSegments {
                    fade(parameters, over: segment.range, fadeOut: !segment.playsOn, volume: key == .voice ? segment.voice : segment.system)
                }
            case .overlayAudio(let index):
                parameters.setVolume(Float(SoundLevel.volume(forGain: timeline.overlays[index].overlay.level)), at: .zero)
            default:
                break
            }
            return parameters
        }

        return BuiltComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            timeline: timeline,
            panels: panels.map { ($0.output, $0.rect) },
            audioTrackIDs: lanes.audioLanes.map(\.1.trackID)
        )
    }

    /// A clip's played range split where freezes hold it, each piece with the frame it holds, if any.
    static func pieces(of range: TimeRange, holds: [Freeze]) -> [(range: TimeRange, frame: TimeInterval?)] {
        var cuts: Set<TimeInterval> = [range.start, range.end]
        for hold in holds where hold.range.overlaps(range) {
            cuts.insert(max(range.start, hold.range.start))
            cuts.insert(min(range.end, hold.range.end))
        }
        let times = cuts.sorted()
        var pieces: [(range: TimeRange, frame: TimeInterval?)] = []
        for (start, end) in zip(times, times.dropFirst()) where end - start > 1e-6 {
            let middle = (start + end) / 2
            let frame = holds.last { $0.range.start <= middle && middle < $0.range.end }?.frame
            if let last = pieces.last, last.frame == nil, frame == nil {
                pieces[pieces.count - 1].range.end = end
            } else {
                pieces.append((TimeRange(start: start, end: end), frame))
            }
        }
        return pieces
    }

    /// The source and track a clip's sound comes from: the one it names, or its source's own.
    static func audio(for clip: Clip, source: Source, project: Project) -> (Source, SourceTrack)? {
        if let choice = clip.audio {
            guard let other = project.source(choice.source), let track = other.track(choice.track) else { return nil }
            return (other, track)
        }
        return source.primaryAudioTrack.map { (source, $0) }
    }

    /// The edit's frame clock (``RenderFrameRate``), which FCPXML uses too.
    static func frameRate(_ project: Project, timeline: EditTimeline) -> Int {
        RenderFrameRate.standard(for: project, playing: timeline.clips.map(\.clip.source))
    }

    static func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(value: CMTimeValue((seconds * Double(timescale)).rounded()), timescale: timescale)
    }

    static func cmRange(_ range: TimeRange) -> CMTimeRange {
        let start = cmTime(range.start)
        return CMTimeRange(start: start, end: cmTime(range.end))
    }

    private static func joined(_ instructions: [LayoutInstruction]) -> [LayoutInstruction] {
        var result: [LayoutInstruction] = []
        var start = CMTime.zero
        for instruction in instructions {
            let end = instruction.timeRange.end
            guard end > start else { continue }
            result.append(instruction.covering(CMTimeRange(start: start, end: end)))
            start = end
        }
        return result
    }

    private static func fade(_ parameters: AVMutableAudioMixInputParameters, over range: TimeRange, fadeOut: Bool, volume: Float) {
        let length = min(joinFade, range.duration / 2)
        guard length > 0 else {
            parameters.setVolume(volume, at: cmTime(range.start))
            return
        }
        parameters.setVolumeRamp(
            fromStartVolume: 0,
            toEndVolume: volume,
            timeRange: cmRange(TimeRange(start: range.start, end: range.start + length))
        )
        if fadeOut {
            parameters.setVolumeRamp(
                fromStartVolume: volume,
                toEndVolume: 0,
                timeRange: cmRange(TimeRange(start: range.end - length, end: range.end))
            )
        }
    }
}

/// The composition's tracks, made as they're first needed, with the assets they read from.
private struct Lanes {
    enum Key: Hashable {
        case screen, camera, video, overlay(Int), voice, system, overlayAudio(Int)

        init(_ kind: SourceTrack.Kind) {
            switch kind {
            case .screen: self = .screen
            case .camera: self = .camera
            default: self = .video
            }
        }

        init(_ role: PictureRole) {
            switch role {
            case .screen: self = .screen
            case .camera: self = .camera
            case .video, .broll: self = .video
            }
        }
    }

    let composition: AVMutableComposition
    let folder: URL
    private var lanes: [Key: AVMutableCompositionTrack] = [:]
    private var assets: [URL: AVURLAsset] = [:]
    private(set) var audioLanes: [(Key, AVMutableCompositionTrack)] = []

    init(composition: AVMutableComposition, folder: URL) {
        self.composition = composition
        self.folder = folder
    }

    func trackID(_ key: Key) -> CMPersistentTrackID? {
        lanes[key]?.trackID
    }

    /// Inserts the part of a track's file that plays a stretch of its source's time, at `rate` times speed.
    ///
    /// Sound that starts after the stretch does, or ends before it, is silent there. A take's screen or
    /// camera holds its nearest frame instead, so a tile is never empty: a take's files are cut to start and
    /// end together (docs/decisions.md, 87), and this covers what a later change to the lip sync moves the
    /// camera off by, and a take whose files couldn't be cut.
    mutating func insert(
        _ track: SourceTrack,
        file override: URL? = nil,
        mediaType: AVMediaType,
        lane key: Key,
        sourceRange: TimeRange,
        at start: TimeInterval,
        rate: Double = 1
    ) async throws {
        let url = override ?? track.file.url(relativeTo: folder)
        guard let (assetTrack, duration) = try await load(url, mediaType: mediaType) else { return }
        let fileStart = sourceRange.start - track.startOffset
        let fileEnd = sourceRange.end - track.startOffset
        let holdsEdges = mediaType == .video && (track.kind == .screen || track.kind == .camera)
        // What the file has of the stretch, kept inside it: with nothing, where the nearest frame is.
        let from = min(max(0, fileStart), max(fileStart, fileEnd))
        let to = max(from, min(duration, fileEnd))
        let frame = holdsEdges ? try await frameLength(of: assetTrack) : 0
        // In timeline order, since a lane is only ever added to at its end: before the file's first frame,
        // that frame; then what the file has; then, past its last frame, the last one.
        if holdsEdges {
            try hold(assetTrack, url: url, lane: key, fileTime: 0, frameLength: frame,
                     from: start, to: start + (from - fileStart) / rate)
        }
        let at = CompositionBuilder.cmTime(start + (from - fileStart) / rate)
        let end = CompositionBuilder.cmTime(start + (to - fileStart) / rate)
        let targetDuration = CMTimeSubtract(end, at)
        if to > from, targetDuration > .zero {
            let lane = try lane(key, mediaType: mediaType)
            do {
                let range = CompositionBuilder.cmRange(TimeRange(start: from, end: to))
                try lane.insertTimeRange(range, of: assetTrack, at: at)
                // Round absolute boundaries, not the duration separately. Otherwise adjacent segments can
                // overlap by one sample; insertion splits off a tiny tail that AVPlayer cannot decode.
                if targetDuration != range.duration {
                    lane.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: targetDuration)
                }
            } catch {
                throw RenderError.unreadableFile(url, error.localizedDescription)
            }
        }
        if holdsEdges {
            try hold(assetTrack, url: url, lane: key, fileTime: max(0, duration - frame), frameLength: frame,
                     from: start + (to - fileStart) / rate, to: start + (fileEnd - fileStart) / rate)
        }
    }

    private func frameLength(of assetTrack: AVAssetTrack) async throws -> TimeInterval {
        let rate = Double((try? await assetTrack.load(.nominalFrameRate)) ?? 30)
        return 1 / (rate > 0 ? rate : 30)
    }

    /// Holds one frame of a file over a stretch of the timeline. Nothing when the stretch is empty.
    private mutating func hold(_ assetTrack: AVAssetTrack, url: URL, lane key: Key, fileTime: TimeInterval, frameLength: TimeInterval,
                               from start: TimeInterval, to end: TimeInterval) throws {
        let at = CompositionBuilder.cmTime(start)
        let held = CMTimeSubtract(CompositionBuilder.cmTime(end), at)
        guard held > .zero else { return }
        let lane = try lane(key, mediaType: .video)
        do {
            let range = CMTimeRange(start: CMTime(seconds: fileTime, preferredTimescale: 600_000), duration: CMTime(seconds: frameLength, preferredTimescale: 600_000))
            try lane.insertTimeRange(range, of: assetTrack, at: at)
            lane.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: held)
        } catch {
            throw RenderError.unreadableFile(url, error.localizedDescription)
        }
    }

    /// Inserts one frame of a track, at a moment of its source's time, held for `seconds`.
    mutating func insertFrame(_ track: SourceTrack, lane key: Key, sourceTime: TimeInterval, at start: TimeInterval, lasting seconds: TimeInterval) async throws {
        let url = track.file.url(relativeTo: folder)
        guard seconds > 0, let (assetTrack, duration) = try await load(url, mediaType: .video) else { return }
        let rate = Double((try? await assetTrack.load(.nominalFrameRate)) ?? 30)
        let frameLength = 1 / (rate > 0 ? rate : 30)
        let fileTime = min(max(0, sourceTime - track.startOffset), max(0, duration - frameLength))
        let lane = try lane(key, mediaType: .video)
        let at = CompositionBuilder.cmTime(start)
        do {
            let range = CMTimeRange(start: CMTime(seconds: fileTime, preferredTimescale: 600_000), duration: CMTime(seconds: frameLength, preferredTimescale: 600_000))
            try lane.insertTimeRange(range, of: assetTrack, at: at)
            let end = CompositionBuilder.cmTime(start + seconds)
            lane.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: CMTimeSubtract(end, at))
        } catch {
            throw RenderError.unreadableFile(url, error.localizedDescription)
        }
    }

    /// A video file's picture size, as it displays.
    mutating func naturalSize(of url: URL) async throws -> CGSize? {
        guard let (track, _) = try await load(url, mediaType: .video) else { return nil }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let shown = size.applying(transform)
        return CGSize(width: abs(shown.width), height: abs(shown.height))
    }

    private mutating func load(_ url: URL, mediaType: AVMediaType) async throws -> (AVAssetTrack, TimeInterval)? {
        let asset = try asset(url)
        do {
            guard let track = try await asset.loadTracks(withMediaType: mediaType).first else { return nil }
            return (track, try await asset.load(.duration).seconds)
        } catch {
            throw RenderError.unreadableFile(url, error.localizedDescription)
        }
    }

    private mutating func lane(_ key: Key, mediaType: AVMediaType) throws -> AVMutableCompositionTrack {
        if let lane = lanes[key] { return lane }
        guard let lane = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RenderError.exportFailed("Couldn't add a track to the composition.")
        }
        lanes[key] = lane
        if mediaType == .audio { audioLanes.append((key, lane)) }
        return lane
    }

    private mutating func asset(_ url: URL) throws -> AVURLAsset {
        if let asset = assets[url] { return asset }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw RenderError.missingFile(url) }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        assets[url] = asset
        return asset
    }
}

import CoreGraphics
import Foundation
import ImageIO
import ProjectKit

/// Writes the edit as an FCPXML timeline for Final Cut Pro or DaVinci Resolve: the export "for another
/// editor" (docs/decisions.md, 14 and 60).
///
/// - **The timeline is always the edit.** One project per output the format includes (the 16:9 video, the
///   9:16 Short), each clip laid out as previewed: the main picture on the primary storyline, the camera
///   connected above it with its position, scale and crop, overlays above that.
/// - **The media is referenced where it is,** in the project folder: the raw screen and camera, system
///   audio, and the mic twice, as recorded (disabled) and cleaned without Voice or loudness, since those
///   belong to the other editor's mix.
/// - **Split at silences** blades every clip at each silence it plays and marks the silent pieces with a
///   "Silence" keyword and role, so they can all be found and deleted at once.
///
/// VERIFY in Final Cut and Resolve: the transform units (position in percent of the frame's height, scale
/// against the clip fitted to the frame), the trim crop, retiming maps for speed and freezes, whether
/// Resolve imports both projects and the camera's sizing through "Use sizing information", and Mirror as a
/// negative scale. Every layout (docs/decisions.md, 66) is placed from ``LayoutGeometry``, as the preview draws
/// it; the look's rounded corners, the camera's hairline and the background colour aren't written, so they
/// come out square, edgeless and black.
public enum FCPXMLWriter {
    /// What to reference for one source's sound, beyond its own tracks.
    public struct SourceAudio: Sendable {
        /// The mic cleaned with Cleanup only, no Voice or loudness, if one was made.
        public var cleanedMic: URL?

        public init(cleanedMic: URL? = nil) {
            self.cleanedMic = cleanedMic
        }
    }

    public struct Options: Sendable {
        public var outputs: [OutputShape]
        public var splitAtSilences: Bool

        public init(outputs: [OutputShape], splitAtSilences: Bool = false) {
            self.outputs = outputs
            self.splitAtSilences = splitAtSilences
        }
    }

    /// The FCPXML document for an edit.
    public static func document(_ inputs: RenderInputs, options: Options, audio: [SourceID: SourceAudio] = [:]) throws -> String {
        let edit = inputs.edit
        let timeline = EditTimeline(edit: edit, transcripts: inputs.transcripts)
        guard !timeline.clips.isEmpty else { throw RenderError.emptyEdit }
        let fps = CompositionBuilder.frameRate(inputs.project, timeline: timeline)
        var resources = Resources(folder: inputs.folder.url, fps: fps)

        var projects: [String] = []
        for output in options.outputs {
            let format = resources.sequenceFormat(width: output.width, height: output.height)
            var spine: [String] = []
            var position = 0
            for placed in timeline.clips {
                guard let source = inputs.project.source(placed.clip.source) else { continue }
                for piece in pieces(of: placed, transcripts: inputs.transcripts, split: options.splitAtSilences, freezes: edit.freezes) {
                    let length = max(1, frames(piece.timeline.duration, fps))
                    let element = try clipElement(
                        placed: placed, piece: piece, source: source, output: output, offset: position, length: length,
                        resources: &resources, inputs: inputs, audio: audio[source.id], timeline: timeline
                    )
                    spine.append(element)
                    position += length
                }
            }
            let name = escape("\(inputs.project.title) \(output == .landscape ? "16x9" : "9x16")")
            projects.append("""
                    <project name="\(name)">
                      <sequence format="\(format)" duration="\(time(position, fps))" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
                        <spine>
                \(spine.joined(separator: "\n"))
                        </spine>
                      </sequence>
                    </project>
                """)
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE fcpxml>
            <fcpxml version="1.10">
              <resources>
            \(resources.xml)
              </resources>
              <library>
                <event name="\(escape(inputs.project.title))">
            \(projects.joined(separator: "\n"))
                </event>
              </library>
            </fcpxml>

            """
    }

    /// Writes the document to a file.
    public static func write(_ inputs: RenderInputs, options: Options, audio: [SourceID: SourceAudio] = [:], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try document(inputs, options: options, audio: audio).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Pieces

    /// One stretch of a clip on the timeline: a piece between silences, a silence, or a freeze.
    struct Piece {
        var source: TimeRange
        var timeline: TimeRange
        var isSilence: Bool
        /// The source time of a held frame.
        var heldFrame: TimeInterval?
    }

    /// A clip's stretches: the whole clip, or, split at silences, the pieces between and the silences. A
    /// freeze always makes a piece of its own.
    static func pieces(of placed: EditTimeline.PlacedClip, transcripts: TranscriptIndex, split: Bool, freezes: [Freeze]) -> [Piece] {
        let played = placed.clip.playedRange
        var cuts: Set<TimeInterval> = [played.start, played.end]
        var silent: [TimeRange] = []
        if split, let transcript = transcripts[placed.clip.source] {
            for silence in transcript.silences where silence.start > played.start + 0.05 && silence.end < played.end - 0.05 {
                silent.append(TimeRange(start: silence.start, end: silence.end))
                cuts.formUnion([silence.start, silence.end])
            }
        }
        let holds = freezes.filter { $0.source == placed.clip.source && $0.range.overlaps(played) }
        for hold in holds { cuts.formUnion([max(played.start, hold.range.start), min(played.end, hold.range.end)]) }
        let times = cuts.sorted()
        return zip(times, times.dropFirst()).compactMap { start, end in
            guard end - start > 0.001 else { return nil }
            let middle = (start + end) / 2
            return Piece(
                source: TimeRange(start: start, end: end),
                timeline: TimeRange(start: placed.timelineTime(ofSourceTime: start), end: placed.timelineTime(ofSourceTime: end)),
                isSilence: silent.contains { $0.start <= middle && middle < $0.end },
                heldFrame: holds.last { $0.range.start <= middle && middle < $0.range.end }?.frame
            )
        }
    }

    // MARK: - Clips

    private static func clipElement(
        placed: EditTimeline.PlacedClip,
        piece: Piece,
        source: Source,
        output: OutputShape,
        offset: Int,
        length: Int,
        resources: inout Resources,
        inputs: RenderInputs,
        audio: SourceAudio?,
        timeline: EditTimeline
    ) throws -> String {
        let fps = resources.fps
        let clip = placed.clip
        let pictures = ClipPictures(source: source, cameraFramings: inputs.edit.framings(for: source.id))
        let frame = LayoutGeometry.frame(for: clip.layout, in: output, pictures: pictures, look: inputs.edit.look(of: clip),
                                         screenTransform: clip.screenTransform, cameraTransform: clip.cameraTransform)
        let size = CGSize(width: output.width, height: output.height)

        // The main picture sits on the storyline; everything else connects to it.
        let main = frame.placements.first
        let mainTrack = main.flatMap { track(for: $0.role, in: source) }
        var connected: [String] = []
        let role = piece.isSilence ? " videoRole=\"Silence\"" : ""

        func start(of track: SourceTrack, at sourceTime: TimeInterval) -> Int {
            frames(max(0, sourceTime - track.startOffset), fps)
        }

        // The parent's local time starts at its own start; connected clips are placed in that time.
        let parentTrack = mainTrack ?? source.primaryAudioTrack
        guard let parentTrack else { return "          <gap offset=\"\(time(offset, fps))\" duration=\"\(time(length, fps))\"/>" }
        let parentStart = start(of: parentTrack, at: piece.source.start)
        let keyword = piece.isSilence ? "\n      <keyword start=\"\(time(parentStart, fps))\" duration=\"\(time(length, fps))\" value=\"Silence\"/>" : ""

        for placement in frame.placements.dropFirst() {
            guard let track = track(for: placement.role, in: source), let video = track.media.video else { continue }
            let asset = try resources.asset(for: track.file, media: track.media)
            connected.append(
                assetClip(ref: asset, lane: 1, offset: parentStart, start: start(of: track, at: piece.source.start), length: length, fps: fps,
                          name: track.kind.rawValue, extra: transform(placement, picture: CGSize(width: video.width, height: video.height), frame: size) + retime(piece, clip: clip, fps: fps, track: track, holds: false), audio: false)
            )
        }

        // Overlays over this stretch, above the camera.
        var lane = 2
        for item in timeline.overlays where item.timeline.overlaps(piece.timeline) {
            let from = max(item.timeline.start, piece.timeline.start)
            let to = min(item.timeline.end, piece.timeline.end)
            let at = parentStart + frames(from - piece.timeline.start, fps)
            let duration = max(1, frames(to - from, fps))
            let slot = (item.overlay.placement == .inScreensPlace ? frame.placement(.screen)?.frame : nil) ?? CGRect(origin: .zero, size: size)
            switch item.overlay.media {
            case .file(let file, let still):
                let url = file.url(relativeTo: inputs.folder.url)
                if still {
                    let picture = CGImageSourceSize(url) ?? size
                    let ref = resources.stillAsset(file)
                    let placement = LayoutGeometry.overlay(size: picture, into: slot, isStill: true)
                    connected.append("    <video ref=\"\(ref)\" lane=\"\(lane)\" offset=\"\(time(at, fps))\" duration=\"\(time(duration, fps))\" name=\"\(escape(url.lastPathComponent))\">\(transform(placement, picture: picture, frame: size))</video>")
                } else {
                    let ref = try resources.asset(for: file, media: MediaInfo(duration: 3600, video: .init(width: Int(size.width), height: Int(size.height), frameRate: Double(fps), captureRate: fps, codec: "")))
                    connected.append(assetClip(ref: ref, lane: lane, offset: at, start: frames(item.mediaTime(at: from), fps), length: duration, fps: fps, name: url.lastPathComponent, extra: "", audio: item.overlay.playsSound))
                }
            case .source(let id):
                guard let other = inputs.project.source(id), let track = other.track(.video) ?? other.track(.camera) ?? other.track(.screen), let video = track.media.video else { continue }
                let ref = try resources.asset(for: track.file, media: track.media)
                let placement = LayoutGeometry.overlay(size: CGSize(width: video.width, height: video.height), into: slot, isStill: false)
                connected.append(assetClip(ref: ref, lane: lane, offset: at, start: frames(item.mediaTime(at: from), fps), length: duration, fps: fps, name: other.name,
                                           extra: transform(placement, picture: CGSize(width: video.width, height: video.height), frame: size), audio: item.overlay.playsSound))
            }
            lane += 1
        }

        // The sound, below the storyline: the cleaned mic, the mic as recorded (off), system audio.
        let sounding = !clip.isMuted && clip.speed.sound != .muted
        var audioLane = -1
        if let mic = source.primaryAudioTrack, mic.kind != .video {
            if let cleaned = audio?.cleanedMic {
                let ref = try resources.asset(for: .external(cleaned), media: MediaInfo(duration: mic.media.duration, audio: mic.media.audio))
                connected.append(assetClip(ref: ref, lane: audioLane, offset: parentStart, start: start(of: mic, at: piece.source.start), length: length, fps: fps, name: "Mic, cleaned", extra: retime(piece, clip: clip, fps: fps, track: mic, holds: false), audio: true, video: false, enabled: sounding))
                audioLane -= 1
            }
            let ref = try resources.asset(for: mic.file, media: mic.media)
            connected.append(assetClip(ref: ref, lane: audioLane, offset: parentStart, start: start(of: mic, at: piece.source.start), length: length, fps: fps, name: "Mic, as recorded", extra: retime(piece, clip: clip, fps: fps, track: mic, holds: false), audio: true, video: false, enabled: sounding && audio?.cleanedMic == nil))
            audioLane -= 1
        }
        if let system = source.track(.systemAudio) {
            let ref = try resources.asset(for: system.file, media: system.media)
            connected.append(assetClip(ref: ref, lane: audioLane, offset: parentStart, start: start(of: system, at: piece.source.start), length: length, fps: fps, name: "System audio", extra: retime(piece, clip: clip, fps: fps, track: system, holds: false), audio: true, video: false, enabled: sounding))
        }

        let parentRef = try resources.asset(for: parentTrack.file, media: parentTrack.media)
        let parentExtra = (main.flatMap { placement in parentTrack.media.video.map { transform(placement, picture: CGSize(width: $0.width, height: $0.height), frame: size) } } ?? "")
            + retime(piece, clip: clip, fps: fps, track: parentTrack, holds: mainTrack != nil)
        let body = ([parentExtra.isEmpty ? nil : parentExtra, keyword.isEmpty ? nil : keyword] + connected.map { "\n" + $0 }).compactMap { $0 }.joined()
        let name = escape("\(clip.id)\(piece.isSilence ? " silence" : "")")
        return """
                      <asset-clip ref="\(parentRef)" offset="\(time(offset, fps))" name="\(name)" start="\(time(parentStart, fps))" duration="\(time(length, fps))"\(role) audioRole="dialogue"\(mainTrack == nil ? "" : " tcFormat=\"NDF\"")>\(body)
                      </asset-clip>
            """
    }

    private static func assetClip(ref: String, lane: Int, offset: Int, start: Int, length: Int, fps: Int, name: String, extra: String, audio: Bool, video: Bool = true, enabled: Bool = true) -> String {
        let attributes = [
            "ref=\"\(ref)\"", "lane=\"\(lane)\"", "offset=\"\(time(offset, fps))\"", "name=\"\(escape(name))\"",
            "start=\"\(time(start, fps))\"", "duration=\"\(time(length, fps))\"",
            video ? nil : "srcEnable=\"audio\"", (!audio && video) ? "srcEnable=\"video\"" : nil,
            audio ? "audioRole=\"dialogue\"" : nil, enabled ? nil : "enabled=\"0\"",
        ].compactMap { $0 }
        return "    <asset-clip \(attributes.joined(separator: " "))>\(extra)</asset-clip>"
    }

    /// The track a picture comes from.
    private static func track(for role: PictureRole, in source: Source) -> SourceTrack? {
        switch role {
        case .screen: source.track(.screen)
        case .camera: source.track(.camera)
        case .video, .broll: source.track(.video)
        }
    }

    // MARK: - Transforms

    /// A placement as Final Cut's transform and crop, against the clip fitted to the frame. VERIFY the units.
    ///
    /// Mirror is a negative horizontal scale, which flips the cropped picture around the clip's middle, so the
    /// crop's offset from that middle flips too. VERIFY in Final Cut and Resolve.
    static func transform(_ placement: Placement, picture: CGSize, frame: CGSize) -> String {
        let fit = min(frame.width / max(picture.width, 1), frame.height / max(picture.height, 1))
        let crop = placement.crop
        let scale = placement.frame.width / max(crop.width * picture.width * fit, 1)
        // Where the crop's middle lands, from the frame's middle, in pixels with y up.
        let flip = placement.mirrored ? -1.0 : 1.0
        let cropOffsetX = (crop.midX - 0.5) * picture.width * fit * scale * flip
        let cropOffsetY = (crop.midY - 0.5) * picture.height * fit * scale
        let x = (placement.frame.midX - frame.width / 2) - cropOffsetX
        let y = -((placement.frame.midY - frame.height / 2) - cropOffsetY)
        let unit = frame.height / 100
        var xml = "\n      <adjust-transform position=\"\(number(x / unit)) \(number(y / unit))\" scale=\"\(number(scale * flip)) \(number(scale))\"/>"
        if crop != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let fitted = CGSize(width: picture.width * fit / unit, height: picture.height * fit / unit)
            xml = "\n      <adjust-crop mode=\"trim\"><trim-rect left=\"\(number(crop.minX * fitted.width))\" top=\"\(number(crop.minY * fitted.height))\" right=\"\(number((1 - crop.maxX) * fitted.width))\" bottom=\"\(number((1 - crop.maxY) * fitted.height))\"/></adjust-crop>" + xml
        }
        return xml
    }

    /// A retiming map for a sped-up clip, or, for the held picture only, a held frame: the camera and the
    /// sound play on through a freeze. Values are in the track's own file time. VERIFY in Final Cut and
    /// Resolve.
    static func retime(_ piece: Piece, clip: Clip, fps: Int, track: SourceTrack, holds: Bool) -> String {
        let length = frames(piece.timeline.duration, fps)
        let offset = track.startOffset
        if holds, let held = piece.heldFrame {
            let value = time(frames(max(0, held - offset), fps), fps)
            return "\n      <timeMap><timept time=\"0s\" value=\"\(value)\" interp=\"linear\"/><timept time=\"\(time(length, fps))\" value=\"\(value)\" interp=\"linear\"/></timeMap>"
        }
        guard !clip.speed.isNormal else { return "" }
        return "\n      <timeMap><timept time=\"0s\" value=\"\(time(frames(max(0, piece.source.start - offset), fps), fps))\" interp=\"linear\"/><timept time=\"\(time(length, fps))\" value=\"\(time(frames(max(0, piece.source.end - offset), fps), fps))\" interp=\"linear\"/></timeMap>"
    }

    // MARK: - Writing values

    static func frames(_ seconds: TimeInterval, _ fps: Int) -> Int {
        Int((seconds * Double(fps)).rounded())
    }

    /// A time in frames, as FCPXML's rational seconds.
    static func time(_ frames: Int, _ fps: Int) -> String {
        frames == 0 ? "0s" : "\(frames)/\(fps)s"
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 10_000).rounded() / 10_000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func CGImageSourceSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The document's formats and assets, each written once and referred to by id.
    struct Resources {
        let folder: URL
        let fps: Int
        private var lines: [String] = []
        private var formats: [String: String] = [:]
        private var assets: [String: String] = [:]
        private var next = 1

        init(folder: URL, fps: Int) {
            self.folder = folder
            self.fps = fps
        }

        var xml: String { lines.joined(separator: "\n") }

        private mutating func id() -> String {
            defer { next += 1 }
            return "r\(next)"
        }

        mutating func sequenceFormat(width: Int, height: Int) -> String {
            // Final Cut 12.4 accepts these project attributes without normalizing them on import.
            // Keep the sequence's SDR working space separate from raw media's own color metadata.
            format(width: width, height: height, colorSpace: "1-1-1 (Rec. 709)")
        }

        private mutating func format(width: Int, height: Int, colorSpace: String?) -> String {
            let key = "\(width)x\(height):\(colorSpace ?? "media")"
            if let id = formats[key] { return id }
            let id = id()
            let color = colorSpace.map { " colorSpace=\"\($0)\"" } ?? ""
            lines.append("    <format id=\"\(id)\" frameDuration=\"1/\(fps)s\" width=\"\(width)\" height=\"\(height)\"\(color)/>")
            formats[key] = id
            return id
        }

        mutating func asset(for file: FileReference, media: MediaInfo) throws -> String {
            let url = file.url(relativeTo: folder)
            let key = url.path(percentEncoded: false)
            if let id = assets[key] { return id }
            var format = ""
            if let video = media.video { format = " format=\"\(self.format(width: video.width, height: video.height, colorSpace: nil))\"" }
            let id = id()
            let audio = media.audio.map { " hasAudio=\"1\" audioSources=\"1\" audioChannels=\"\($0.channels)\" audioRate=\"\(Int($0.sampleRate))\"" } ?? ""
            let video = media.video == nil ? "" : " hasVideo=\"1\""
            lines.append("""
                    <asset id="\(id)" name="\(FCPXMLWriter.escape(url.lastPathComponent))" start="0s" duration="\(FCPXMLWriter.time(max(1, FCPXMLWriter.frames(media.duration, fps)), fps))"\(video)\(audio)\(format)>
                      <media-rep kind="original-media" src="\(FCPXMLWriter.escape(url.absoluteString))"/>
                    </asset>
                """)
            assets[key] = id
            return id
        }

        mutating func stillAsset(_ file: FileReference) -> String {
            let url = file.url(relativeTo: folder)
            let key = url.path(percentEncoded: false)
            if let id = assets[key] { return id }
            let id = id()
            lines.append("""
                    <asset id="\(id)" name="\(FCPXMLWriter.escape(url.lastPathComponent))" start="0s" duration="0s" hasVideo="1">
                      <media-rep kind="original-media" src="\(FCPXMLWriter.escape(url.absoluteString))"/>
                    </asset>
                """)
            assets[key] = id
            return id
        }
    }
}

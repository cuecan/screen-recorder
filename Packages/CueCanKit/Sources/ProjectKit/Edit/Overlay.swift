import Foundation

/// A picture or a clip shown on top of the main track: a screenshot, a video file, or another source of the
/// project, such as B-roll (docs/decisions.md, 54; docs/ui.md, E1).
///
/// It's anchored to the main track's words, or to a stretch of a source's time where nothing is said, so it
/// moves with every cut. It shows wherever that stretch plays, playing its own media from ``sourceIn``.
public struct Overlay: Codable, Equatable, Sendable, Identifiable {
    /// What the overlay shows.
    public enum Media: Equatable, Hashable, Sendable {
        /// Another source in the project, such as B-roll footage.
        case source(SourceID)
        /// A file on disk, referenced where it is: a still image, or a video.
        case file(FileReference, isStill: Bool)
    }

    /// Where it sits in the frame.
    public enum Placement: String, Codable, Sendable, CaseIterable {
        /// Over the whole frame, like B-roll: the screen and the camera are hidden.
        case coversFrame
        /// In the screen's place: the camera stays beside it.
        case inScreensPlace

        public var label: String { self == .coversFrame ? "Covers the frame" : "In the screen’s place" }
    }

    /// What it's anchored to.
    public enum Anchor: Equatable, Hashable, Sendable {
        /// A range of the main track's words and pauses.
        case words(ItemRange)
        /// A stretch of one source's time, for where no words help.
        case time(source: SourceID, range: TimeRange)
    }

    public let id: ClipID
    public var media: Media
    /// Where a video starts playing, in its own time.
    public var sourceIn: TimeInterval
    public var over: Anchor
    public var placement: Placement
    /// Whether a video's own sound is off. A video overlay starts muted; a still has no sound.
    public var isMuted: Bool
    /// The level of a video's own sound in the mix, in dB (``SoundLevel``, docs/decisions.md, 71).
    public var level: Double { didSet { level = SoundLevel.clamped(level) } }

    public init(id: ClipID, media: Media, sourceIn: TimeInterval = 0, over: Anchor, placement: Placement = .coversFrame, isMuted: Bool = true, level: Double = 0) {
        self.id = id
        self.media = media
        self.sourceIn = max(0, sourceIn)
        self.over = over
        self.placement = placement
        self.isMuted = isMuted
        self.level = SoundLevel.clamped(level)
    }

    /// Whether it's a still picture, with no time of its own and no sound.
    public var isStill: Bool {
        if case .file(_, let still) = media { return still }
        return false
    }

    /// Whether it plays sound.
    public var playsSound: Bool { !isStill && !isMuted }

    /// A short name for the timeline: the file's name, or the source's id.
    public var name: String {
        switch media {
        case .source(let id): id.description
        case .file(let file, _): URL(filePath: file.path).lastPathComponent
        }
    }

    // Encoded flat: {"id":"c_9","file":"/Users/…/shot.png","still":true,"over":{…},"placement":"inScreensPlace"}.
    // Earlier edits' B-roll, {"id","source","sourceIn","over"}, reads as an overlay covering the frame, muted.
    private enum CodingKeys: String, CodingKey {
        case id, source, file, still, sourceIn, over, overTime, placement, muted, level
    }

    private struct TimeAnchor: Codable {
        var source: SourceID
        var start: TimeInterval
        var end: TimeInterval
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ClipID.self, forKey: .id)
        if let source = try container.decodeIfPresent(SourceID.self, forKey: .source) {
            media = .source(source)
        } else if let path = try container.decodeIfPresent(String.self, forKey: .file) {
            media = .file(FileReference(path: path), isStill: try container.decodeIfPresent(Bool.self, forKey: .still) ?? false)
        } else {
            throw DecodingError.keyNotFound(CodingKeys.file, .init(codingPath: container.codingPath, debugDescription: "An overlay needs a source or a file."))
        }
        sourceIn = max(0, try container.decodeIfPresent(TimeInterval.self, forKey: .sourceIn) ?? 0)
        if let words = try container.decodeIfPresent(ItemRange.self, forKey: .over) {
            over = .words(words)
        } else if let time = try container.decodeIfPresent(TimeAnchor.self, forKey: .overTime) {
            guard time.end > time.start else {
                throw DecodingError.dataCorruptedError(forKey: .overTime, in: container, debugDescription: "An overlay's time has to end after it starts.")
            }
            over = .time(source: time.source, range: TimeRange(start: time.start, end: time.end))
        } else {
            throw DecodingError.keyNotFound(CodingKeys.over, .init(codingPath: container.codingPath, debugDescription: "An overlay needs words or a time to sit over."))
        }
        placement = try container.decode(Placement.self, forKey: .placement)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? true
        level = SoundLevel.clamped(try container.decodeIfPresent(Double.self, forKey: .level) ?? 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch media {
        case .source(let source):
            try container.encode(source, forKey: .source)
        case .file(let file, let still):
            try container.encode(file.path, forKey: .file)
            if still { try container.encode(true, forKey: .still) }
        }
        if sourceIn != 0 { try container.encode(sourceIn, forKey: .sourceIn) }
        switch over {
        case .words(let range): try container.encode(range, forKey: .over)
        case .time(let source, let range): try container.encode(TimeAnchor(source: source, start: range.start, end: range.end), forKey: .overTime)
        }
        try container.encode(placement, forKey: .placement)
        if !isStill { try container.encode(isMuted, forKey: .muted) }
        if !isStill, level != 0 { try container.encode(level, forKey: .level) }
    }
}

extension Overlay.Media {
    /// Image files an overlay can show as a still. Anything else is treated as a video.
    public static let stillExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp"]

    /// A file overlay, still or video by its extension.
    public static func file(at url: URL) -> Self {
        .file(.external(url), isStill: stillExtensions.contains(url.pathExtension.lowercased()))
    }
}

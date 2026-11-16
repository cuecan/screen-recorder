import Foundation

/// `project.json`: what a project is made of. Its sources, and the counters that keep every id unique.
///
/// The edit itself lives in `edit.json` (``Edit``), and each source's transcript in `transcripts/`.
/// Sources never change once they're transcribed, apart from their sync offset, which can be nudged.
public struct Project: Codable, Equatable, Sendable {
    /// The format version of `project.json`. Bump it on any incompatible change.
    public static let currentFormatVersion = 3

    public var formatVersion: Int
    /// A stable identity for the project, so it can be recognized after the folder is renamed or moved.
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var sources: [Source]
    /// Where the video will be posted and its layout. Nil until it's chosen: ``effectiveFormat`` is
    /// then the standard one.
    public var format: VideoFormat?
    /// Names and jargon the video uses, given by the agent (docs/decisions.md, 42). Vocabulary boosting
    /// runs with them on every transcribed source.
    public var vocabulary: [String]
    /// The project this one was duplicated from (docs/decisions.md, 77). Nil for a recording. Written only
    /// for a copy.
    public var copyOf: UUID?

    /// The next number for a source id (`src_<n>`).
    public var nextSourceNumber: Int
    /// The next number for a word id (`w_<n>`). Word ids are unique across every transcript in the project.
    public var nextWordNumber: Int
    /// The next number for a silence id (`s_<n>`). Silence ids are unique across every transcript in the project.
    public var nextSilenceNumber: Int

    public init(id: UUID = UUID(), title: String, createdAt: Date = .now) {
        self.formatVersion = Self.currentFormatVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sources = []
        self.format = nil
        self.vocabulary = []
        self.nextSourceNumber = 1
        self.nextWordNumber = 1
        self.nextSilenceNumber = 1
    }

    /// The project's format, or the standard one if none was chosen.
    public var effectiveFormat: VideoFormat {
        format ?? .standard
    }

    /// The source with this id, if the project has one.
    public func source(_ id: SourceID) -> Source? {
        sources.first { $0.id == id }
    }

    /// Adds a source and gives it the next source id.
    @discardableResult
    public mutating func addSource(
        name: String,
        origin: Source.Origin,
        tracks: [SourceTrack],
        sync: SourceSync? = nil,
        captureArea: CaptureArea? = nil,
        layout: TakeLayout? = nil
    ) -> Source {
        let source = Source(
            id: SourceID(number: nextSourceNumber),
            name: name,
            origin: origin,
            tracks: tracks,
            sync: sync,
            captureArea: captureArea,
            layout: layout
        )
        nextSourceNumber += 1
        sources.append(source)
        return source
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, title, createdAt, sources, format, vocabulary, copyOf
        case nextSourceNumber, nextWordNumber, nextSilenceNumber
    }
}

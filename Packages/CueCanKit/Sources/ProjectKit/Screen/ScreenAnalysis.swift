import Foundation

/// What the screen track shows over time, found after recording (docs/decisions.md, 58): when the screen
/// changes and when it goes still, and, at each still moment, the text in the capture area.
///
/// Stored as `screen/<source>.analysis.json`, in source time like the transcripts, so every cut maps onto it.
/// It's regenerable from the screen track. The text stays in the project folder and reaches an agent only
/// through `get_screen_timeline` and `find_on_screen`.
public struct ScreenAnalysis: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    /// A stretch where the screen kept changing: typing, scrolling, a page loading.
    public struct Change: Codable, Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval

        public init(start: TimeInterval, end: TimeInterval) {
            self.start = start
            self.end = end
        }
    }

    /// A line of text read on screen, with where it was.
    public struct TextLine: Codable, Equatable, Sendable {
        public var text: String
        /// Where, as fractions of the capture area from its top left: x, y, width, height.
        public var box: [Double]
        public var confidence: Double

        public init(text: String, box: [Double], confidence: Double) {
            self.text = text
            self.box = box
            self.confidence = confidence
        }
    }

    /// A moment the screen went still and stayed so for a while: a good place to look, and a snap point.
    public struct Still: Codable, Equatable, Sendable {
        /// When it went still.
        public var start: TimeInterval
        /// When it next changed, or the end of the recording.
        public var end: TimeInterval
        /// The text on screen, when reading it is on. Nil when it wasn't read.
        public var text: [TextLine]?

        public init(start: TimeInterval, end: TimeInterval, text: [TextLine]? = nil) {
            self.start = start
            self.end = end
            self.text = text
        }

        /// The text as one string, line by line.
        public var plainText: String { (text ?? []).map(\.text).joined(separator: "\n") }
    }

    public var formatVersion: Int
    public var source: SourceID
    public var createdAt: Date
    /// How often the screen was looked at, in frames a second.
    public var sampleRate: Double
    /// Whether the text was read ("Save screen text").
    public var readText: Bool
    public var changes: [Change]
    public var stills: [Still]

    public init(source: SourceID, createdAt: Date = .now, sampleRate: Double, readText: Bool, changes: [Change], stills: [Still]) {
        self.formatVersion = Self.currentFormatVersion
        self.source = source
        self.createdAt = createdAt
        self.sampleRate = sampleRate
        self.readText = readText
        self.changes = changes
        self.stills = stills
    }

    /// The stills whose text contains `query`, ignoring case and accents, each with the lines that match.
    public func find(_ query: String) -> [(still: Still, lines: [TextLine])] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return stills.compactMap { still in
            let lines = (still.text ?? []).filter { $0.text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return lines.isEmpty ? nil : (still, lines)
        }
    }
}

extension ProjectFolder {
    /// Where a source's screen analysis is stored.
    public func screenAnalysisURL(for source: SourceID) -> URL {
        url(for: .screen).appending(path: "\(source).analysis.json")
    }

    /// A source's screen analysis, or nil if it hasn't been made.
    public func loadScreenAnalysis(for source: SourceID) throws(ProjectFolderError) -> ScreenAnalysis? {
        let fileURL = screenAnalysisURL(for: source)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        return try read(fileURL)
    }

    /// Saves a source's screen analysis, replacing any earlier one.
    public func saveScreenAnalysis(_ analysis: ScreenAnalysis) throws {
        try withLock {
            guard try loadProject().source(analysis.source) != nil else { throw EditError.unknownSource(analysis.source) }
            do {
                try FileManager.default.createDirectory(at: url(for: .screen), withIntermediateDirectories: true)
            } catch {
                throw ProjectFolderError.couldNotWrite(url(for: .screen), error.localizedDescription)
            }
            try write(analysis, to: screenAnalysisURL(for: analysis.source))
        }
    }

    /// A source's screen log events, if it has a log (``ScreenLog``).
    public func loadScreenLogEvents(for source: Source) -> [ScreenLog.Event] {
        guard let name = source.screenLog else { return [] }
        return (try? ScreenLog.read(ScreenLog.Event.self, from: ScreenLog.eventsURL(name, in: url))) ?? []
    }

    /// A source's pointer path, if it has a log.
    public func loadPointerPath(for source: Source) -> [ScreenLog.PointerSample] {
        guard let name = source.screenLog else { return [] }
        return (try? ScreenLog.read(ScreenLog.PointerSample.self, from: ScreenLog.pointerURL(name, in: url))) ?? []
    }
}

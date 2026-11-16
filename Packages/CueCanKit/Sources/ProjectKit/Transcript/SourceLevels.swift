import Foundation

/// What the silence detector measured on a source's main audio (docs/decisions.md, 40 and 75): each short
/// frame's level, and the detector's own threshold between quiet and sound. Saved beside the cleaned voice in
/// `audio/`, so the tools can check cut edges by their sound without reading the recording again.
public struct SourceLevels: Codable, Sendable, Equatable {
    public static let currentFormat = 1

    public var formatVersion: Int
    public var source: SourceID
    /// The track measured. Levels from another file don't apply.
    public var original: FileReference
    /// The detector, such as "energy".
    public var detector: String
    /// Frames below this level, in dB, are quiet.
    public var threshold: Double
    /// The detector's own: sound shorter than this between quiet frames, such as a click, doesn't count.
    public var minimumSound: TimeInterval
    public var frameDuration: TimeInterval
    /// The source time frame 0 starts at: the track's start offset.
    public var start: TimeInterval
    /// Each frame's level in tenths of a dB, as little-endian 16-bit integers.
    public var levels: Data

    public init(source: SourceID, original: FileReference, detector: String, threshold: Double, minimumSound: TimeInterval,
                envelope: SoundEnvelope) {
        formatVersion = Self.currentFormat
        self.source = source
        self.original = original
        self.detector = detector
        self.threshold = threshold
        self.minimumSound = minimumSound
        frameDuration = envelope.frameDuration
        start = envelope.start
        var data = Data(capacity: envelope.levels.count * 2)
        for level in envelope.levels {
            let tenths = Int16(clamping: Int((max(-3000, min(3000, level * 10))).rounded()))
            withUnsafeBytes(of: tenths.littleEndian) { data.append(contentsOf: $0) }
        }
        levels = data
    }

    /// The levels in dB, to a tenth.
    public var envelope: SoundEnvelope {
        var values: [Double] = []
        values.reserveCapacity(levels.count / 2)
        levels.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: bytes.count - 1, by: 2) {
                let tenths = Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                values.append(Double(tenths) / 10)
            }
        }
        return SoundEnvelope(levels: values, frameDuration: frameDuration, start: start)
    }
}

extension ProjectFolder {
    /// Where a source's measured levels are stored.
    public func levelsURL(for source: SourceID) -> URL {
        url(for: .audio).appending(path: "\(source)-levels.json")
    }

    /// A source's measured levels, if they were measured from this track. Nil when there are none, or they
    /// came from another file or an older format.
    public func loadLevels(for source: SourceID, original: FileReference) -> SourceLevels? {
        let fileURL = levelsURL(for: source)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)),
            let levels: SourceLevels = try? read(fileURL),
            levels.formatVersion == SourceLevels.currentFormat, levels.original == original
        else { return nil }
        return levels
    }

    public func saveLevels(_ levels: SourceLevels) throws(ProjectFolderError) {
        try? FileManager.default.createDirectory(at: url(for: .audio), withIntermediateDirectories: true)
        try write(levels, to: levelsURL(for: levels.source))
    }
}

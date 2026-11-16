import AudioKit
import Foundation
import ProjectKit
import TranscribeKit

/// Each source's measured levels for checking cut edges (docs/decisions.md, 75): read from `audio/` when
/// they were measured from the current track, else measured with the silence detector and saved.
public enum SourceLevelsMeasure {
    /// The levels for each source that plays sound in the edit. A source whose audio can't be read is left out.
    public static func levels(for sources: Set<SourceID>, in folder: ProjectFolder) async -> [SourceID: SourceLevels] {
        var found: [SourceID: SourceLevels] = [:]
        for source in sources {
            if let levels = try? await levels(for: source, in: folder) { found[source] = levels }
        }
        return found
    }

    /// A source's levels, measured now if they haven't been. Nil for a source with no audio.
    public static func levels(for id: SourceID, in folder: ProjectFolder) async throws -> SourceLevels? {
        guard let source = try folder.loadProject().source(id), let track = source.primaryAudioTrack else { return nil }
        if let saved = folder.loadLevels(for: id, original: track.file) { return saved }
        let url = track.file.url(relativeTo: folder.url)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { throw ProcessingError.missingFile(url) }
        let audio = try await AudioFileReader.readMono(url, track: 0, sampleRate: 48_000)
        let detector = EnergySilenceDetector()
        let levels = record(detector.analyze(audio), by: detector, for: id, track: track)
        try folder.saveLevels(levels)
        return levels
    }

    /// What the detector measured, as a record for `audio/`, in the source's time.
    static func record(_ analysis: EnergySilenceDetector.Analysis, by detector: EnergySilenceDetector, for id: SourceID, track: SourceTrack) -> SourceLevels {
        let measured = analysis.envelope
        return SourceLevels(source: id, original: track.file, detector: detector.id, threshold: analysis.threshold,
                            minimumSound: detector.settings.minimumSound,
                            envelope: SoundEnvelope(levels: measured.levels, frameDuration: measured.frameDuration, start: track.startOffset))
    }
}

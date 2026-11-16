import Foundation
import ProjectKit

/// Closes every track before reporting failures, including the mic after a video encoder fails.
/// Closures keep this shutdown policy testable without capture hardware.
enum RecordingFinalizer {
    struct Track: Sendable {
        let kind: SourceTrack.Kind
        let url: URL
        let finish: @Sendable () async throws -> TimeInterval?
    }

    /// A track that couldn't be closed, and why.
    struct Failure: Sendable, Equatable {
        let kind: SourceTrack.Kind
        let url: URL
        let message: String
    }

    /// A closed or recovered file that was successfully inspected, with its original clock placement.
    struct MediaTrack: Sendable {
        let kind: SourceTrack.Kind
        let url: URL
        let first: TimeInterval
        let media: MediaInfo
    }

    /// Inspect each file independently, including a failed mic's crash-safe WAV. An unreadable file
    /// must not prevent other tracks from being saved. Each file is probed at most once.
    static func recover(written: [(SourceTrack.Kind, URL, TimeInterval)], failed: [Failure],
                        firstTimes: [SourceTrack.Kind: TimeInterval?],
                        probe: @Sendable (SourceTrack.Kind, URL) async throws -> MediaInfo) async -> (tracks: [MediaTrack], lost: [Failure]) {
        var candidates = written
        var lost: [Failure] = []
        for failure in failed {
            if let first = firstTimes[failure.kind] ?? nil { candidates.append((failure.kind, failure.url, first)) }
            else { lost.append(failure) }
        }
        var tracks: [MediaTrack] = []
        for (kind, url, first) in candidates {
            do {
                let media = try await probe(kind, url)
                guard media.duration.isFinite, media.duration > 0 else { throw RecorderError.nothingRecorded }
                tracks.append(MediaTrack(kind: kind, url: url, first: first, media: media))
            } catch {
                lost.append(Failure(kind: kind, url: url, message: error.localizedDescription))
            }
        }
        return (tracks, lost)
    }

    /// A take's tracks as they go into the project, and where source time zero fell on the recording's clock.
    struct Placed: Sendable {
        var tracks: [SourceTrack]
        var origin: TimeInterval
        /// The lip sync the camera was placed by.
        var lipSync: TimeInterval
        /// Whether the files were cut to the time they all cover.
        var isCut: Bool
    }

    /// Cuts the files to the time every picture and the voice cover (``TakeSpan``), so each starts at source
    /// time zero and they end together. If they can't be cut, the take is kept as it was recorded, each track
    /// placed by its first sample and the camera earlier by its lip sync: nothing recorded is lost to a
    /// failed cut.
    static func place(_ tracks: [MediaTrack], lipSync: TimeInterval, file: (MediaTrack) -> FileReference,
                      trim: @Sendable ([(url: URL, keep: TimeRange)]) async throws -> Void,
                      probe: @Sendable (SourceTrack.Kind, URL) async throws -> MediaInfo) async throws -> Placed? {
        let spans = tracks.map { TakeSpan.Track(kind: $0.kind, first: $0.first, duration: $0.media.duration) }
        let shift = TakeSpan.lipSync(lipSync, for: spans.map(\.kind))
        let starts = tracks.map { $0.first - ($0.kind == .camera ? shift : 0) }
        guard let earliest = starts.min() else { return nil }
        let asRecorded = Placed(tracks: zip(tracks, starts).map { SourceTrack(kind: $0.kind, file: file($0), startOffset: $1 - earliest, media: $0.media) },
                                origin: earliest, lipSync: shift, isCut: false)
        guard let span = TakeSpan(tracks: spans, lipSync: lipSync) else { return asRecorded }
        let cuts = zip(tracks, spans).compactMap { track, placed in span.cut(for: placed).map { (track, $0) } }
        do {
            try await trim(cuts.map { ($0.0.url, $0.1.keep) })
        } catch let error as TrackTrimPublication.RestorationFailure {
            throw error
        } catch {
            NSLog("CueCan: the take's files couldn't be cut to one length: %@", error.localizedDescription)
            return asRecorded
        }
        // A track with nothing inside the take (system audio that came and went outside it) isn't part of it.
        for track in tracks where !cuts.contains(where: { $0.0.url == track.url }) {
            try? FileManager.default.removeItem(at: track.url)
        }
        var placed: [SourceTrack] = []
        for (track, cut) in cuts {
            var media = track.media
            // The cut file is read again for its length; if that fails, it's as long as what was kept.
            media.duration = (try? await probe(track.kind, track.url))?.duration ?? cut.keep.duration
            placed.append(SourceTrack(kind: track.kind, file: file(track), startOffset: cut.startOffset, media: media))
        }
        return Placed(tracks: placed, origin: span.start, lipSync: span.lipSync, isCut: true)
    }

    /// Every track closed: those written, with where each started, and those that failed. A failure never
    /// stops the other tracks being closed.
    static func finish(_ tracks: [Track]) async -> (written: [(SourceTrack.Kind, URL, TimeInterval)], failed: [Failure]) {
        var written: [(SourceTrack.Kind, URL, TimeInterval)] = []
        var failed: [Failure] = []
        for track in tracks {
            do {
                if let first = try await track.finish() { written.append((track.kind, track.url, first)) }
            } catch {
                failed.append(Failure(kind: track.kind, url: track.url, message: error.localizedDescription))
            }
        }
        return (written, failed)
    }
}

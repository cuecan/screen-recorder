import Foundation
import ProjectKit

/// The stretch of a recording that every picture and the voice cover, which a take is cut to when it's
/// saved (docs/decisions.md, 87).
///
/// Captures start and stop a few milliseconds apart, and sometimes more than a second. Left alone, a take
/// opens on a frame with a tile missing and ends with one gone. So the take is only the time its screen,
/// camera and mic all have: the files are cut to it, and every track then starts at zero and ends together.
///
/// The camera is moved earlier by the take's lip sync before the span is worked out, since that's where its
/// pictures belong against the voice: its file is cut later by the lip sync, so it starts at zero in step.
/// Nothing moves it afterwards (docs/decisions.md, 88). System audio never shortens a take. It's cut to the span where it runs
/// past it, and where it has nothing there's silence.
public struct TakeSpan: Equatable, Sendable {
    /// One recorded file: where its first sample falls on the recording's clock, and how long it runs.
    public struct Track: Equatable, Sendable {
        public var kind: SourceTrack.Kind
        public var first: TimeInterval
        public var duration: TimeInterval

        public init(kind: SourceTrack.Kind, first: TimeInterval, duration: TimeInterval) {
            self.kind = kind
            self.first = first
            self.duration = duration
        }
    }

    /// What to keep of one file, and where it then starts in source time.
    public struct Cut: Equatable, Sendable {
        /// The part of the file to keep, in the file's own time.
        public var keep: TimeRange
        /// The track's ``SourceTrack/startOffset`` once it's cut.
        public var startOffset: TimeInterval
    }

    /// Where the take starts and ends, on the recording's clock. The start is source time zero.
    public let start: TimeInterval
    public let end: TimeInterval
    /// The furthest a camera's picture is moved either way, in seconds.
    public static let lipSyncLimit: TimeInterval = 0.5

    /// The lip sync the camera was placed by: zero without both a camera and sound to be in step with.
    public let lipSync: TimeInterval

    public var duration: TimeInterval { end - start }

    /// Nil when the tracks have no time in common, or there are none.
    public init?(tracks: [Track], lipSync: TimeInterval) {
        self.lipSync = Self.lipSync(lipSync, for: tracks.map(\.kind))
        let setting = tracks.contains { $0.kind.setsLength } ? tracks.filter(\.kind.setsLength) : tracks
        let shift = self.lipSync
        let placed = setting.map { track -> (start: TimeInterval, end: TimeInterval) in
            let start = track.first - (track.kind == .camera ? shift : 0)
            return (start, start + track.duration)
        }
        guard let start = placed.map(\.start).max(), let end = placed.map(\.end).min(), end > start else { return nil }
        self.start = start
        self.end = end
    }

    /// The lip sync a take with these tracks uses: the one measured for its camera and mic, within
    /// ``lipSyncLimit`` and rounded to the millisecond, or zero without both a camera and sound for it to be
    /// in step with.
    public static func lipSync(_ measured: TimeInterval, for kinds: [SourceTrack.Kind]) -> TimeInterval {
        let hasSound = kinds.contains(.microphone) || kinds.contains(.systemAudio)
        guard kinds.contains(.camera), hasSound else { return 0 }
        return (min(lipSyncLimit, max(-lipSyncLimit, measured)) * 1000).rounded() / 1000
    }

    /// What to keep of a track. Nil when none of it is inside the take, which only system audio can be.
    public func cut(for track: Track) -> Cut? {
        let shift = track.kind == .camera ? lipSync : 0
        let placed = track.first - shift
        let from = max(0, start - placed)
        let to = min(track.duration, end - placed)
        guard to > from else { return nil }
        return Cut(keep: TimeRange(start: from, end: to), startOffset: max(0, placed - start))
    }
}

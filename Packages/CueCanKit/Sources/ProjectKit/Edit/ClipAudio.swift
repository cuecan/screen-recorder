import Foundation

/// The audio a clip plays: one track of one source, such as a separate mic synced to the camera.
public struct ClipAudio: Codable, Hashable, Sendable {
    public var source: SourceID
    public var track: SourceTrack.Kind

    public init(source: SourceID, track: SourceTrack.Kind) {
        self.source = source
        self.track = track
    }
}

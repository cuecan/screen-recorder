import Foundation
import ProjectKit

/// What a finished recording made: its tracks, lined up on the host clock, ready to add to a project.
public struct RecordedSource: Sendable, Equatable {
    public var name: String
    public var tracks: [SourceTrack]
    public var captureArea: CaptureArea?
    /// Buffers the encoders had to drop, by track: a sign the Mac was struggling.
    public var droppedBuffers: [SourceTrack.Kind: Int]
    /// When the mic disappeared, in seconds into the recording, if it did.
    public var micLostAt: TimeInterval?
    /// How far the camera's picture was moved earlier to meet the voice, which is cut into its file
    /// (``TakeSpan``). Zero without both a camera and sound.
    public var lipSync: TimeInterval = 0
    /// Where source time zero, the start of the time every track covers, falls on the recording's clock. Anything
    /// logged on that clock, such as the screen log, moves back by this to be in source time.
    public var clockOffset: TimeInterval = 0
    /// The screen log's name in `screen/`, once it's written (``ScreenLog``).
    public var screenLog: String?
    /// Tracks whose file couldn't be closed or read, so the take was saved without them.
    public var lostTracks: [SourceTrack.Kind] = []
    /// Buffers dropped because they didn't move time on from the one before, by track.
    public var outOfOrderBuffers: [SourceTrack.Kind: Int] = [:]

    /// Adds the recording to the project as one source. The first recording also sets the project's format.
    @discardableResult
    public func add(to folder: ProjectFolder, format: VideoFormat?) throws -> Source {
        var added: Source?
        try folder.updateProject { project in
            // A take with a screen was recorded for the format's layout, its shape (docs/decisions.md, 89).
            var source = project.addSource(name: name, origin: .recorded, tracks: tracks, captureArea: captureArea,
                                           layout: captureArea == nil ? nil : format?.layout)
            if let index = project.sources.firstIndex(where: { $0.id == source.id }) {
                source.screenLog = screenLog
                let hasSound = source.track(.microphone) != nil || source.track(.systemAudio) != nil
                source.lipSync = source.track(.camera) != nil && hasSound ? lipSync : nil
                project.sources[index] = source
            }
            added = source
            if project.format == nil { project.format = format }
        }
        guard let added else { throw RecorderError.nothingRecorded }
        return added
    }
}

import Foundation
import ProjectKit

/// A track that stopped recording during a take: its writer failed, its capture stopped, or it went quiet.
/// The take stops there, so a creator never records on believing everything is fine.
public struct TrackFailure: Sendable, Equatable {
    public let kind: SourceTrack.Kind
    /// When it happened, in seconds into the recording.
    public let at: TimeInterval
    public let reason: String

    public init(kind: SourceTrack.Kind, at: TimeInterval, reason: String) {
        self.kind = kind
        self.at = at
        self.reason = reason
    }

    /// The track as a creator calls it.
    public var trackName: String {
        switch kind {
        case .screen: "screen"
        case .camera, .video: "camera"
        case .microphone, .audio: "mic"
        case .systemAudio: "system audio"
        }
    }

    /// What the alert says once the take has stopped, and whether what came before was saved.
    public func message(saved: Bool = true) -> String {
        let time = Duration.seconds(at.rounded(.down)).formatted(.time(pattern: at >= 3600 ? .hourMinuteSecond : .minuteSecond))
        let stopped = "The \(trackName) recording failed at \(time), so CueCan stopped the take there."
        return saved ? "\(stopped) Everything recorded up to then was saved. (\(reason))" : "\(stopped) (\(reason))"
    }

    /// Whether a camera has gone quiet: no frame for `threshold` seconds of recording. Before its first frame,
    /// the recording's start counts as the last.
    public static func isStalled(lastFrame: TimeInterval?, elapsed: TimeInterval, threshold: TimeInterval) -> Bool {
        elapsed - (lastFrame ?? 0) > threshold
    }
}

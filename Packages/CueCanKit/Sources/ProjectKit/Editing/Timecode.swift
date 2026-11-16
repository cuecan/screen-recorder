import Foundation

/// Time as the editor shows it: minutes, seconds and frames, "1:02:15", with hours in front from an hour on,
/// "1:02:03:15". The frame is the one playing at that moment, so stepping a frame moves the last number by one.
public struct Timecode: Sendable, Hashable {
    /// Frames a second, at least 1.
    public let frameRate: Int

    public init(frameRate: Int) {
        self.frameRate = max(1, frameRate)
    }

    /// From a frame's duration in seconds, as a composition gives it: 1/30 is 30 frames a second.
    public init(frameDuration: TimeInterval) {
        self.init(frameRate: frameDuration > 0 ? Int((1 / frameDuration).rounded()) : 30)
    }

    /// The timestamp of the nearest output-frame boundary, for pointer edits that did not snap to a
    /// word, silence or existing cut. The model itself still accepts exact source times.
    public func frameTime(nearest seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        let frames = max(0, seconds) * Double(frameRate)
        guard frames.isFinite else { return 0 }
        return frames.rounded() / Double(frameRate)
    }

    /// The frame immediately before a cut; a cut on a frame boundary belongs to the incoming picture.
    public func frameTime(before seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return max(0, ceil(seconds * Double(frameRate) - 1e-8) - 1) / Double(frameRate)
    }

    /// The first output-frame boundary on or after a cut, including a fractional semantic cut.
    public func frameTime(atOrAfter seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return max(0, ceil(seconds * Double(frameRate) - 1e-8)) / Double(frameRate)
    }

    public func string(_ seconds: TimeInterval) -> String {
        // A hair over, so a time computed as frames × duration lands on its own frame, not the one before.
        let frames = Int((max(0, seconds) * Double(frameRate) + 1e-6).rounded(.down))
        let frame = frames % frameRate
        let totalSeconds = frames / frameRate
        let hours = totalSeconds / 3600
        let minutes = totalSeconds / 60 % 60
        let second = totalSeconds % 60
        let digits = frameRate > 100 ? 3 : 2
        let tail = String(format: "%02d:%0\(digits)d", second, frame)
        return hours > 0 ? String(format: "%d:%02d:", hours, minutes) + tail : "\(minutes):" + tail
    }
}

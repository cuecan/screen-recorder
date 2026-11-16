import Foundation

/// A take opens showing what was recorded, like any editor: the recorder puts the whole source on the main
/// track as one clip when it saves the take (docs/decisions.md, 62). Nothing is cut: the
/// creator and Claude cut from there.
extension Edit {
    /// Puts the whole of a source on the main track, from its start to its end (``Source/duration``), at the
    /// end. It needs no transcript, so a take shows at once, before it's transcribed. `look` is the
    /// camera side chosen while recording.
    @discardableResult
    public mutating func addWholeSource(_ source: Source, look: ClipLook = ClipLook()) -> Clip? {
        guard source.duration > Self.minimumClipDuration else { return nil }
        let clip = Clip(id: makeClipID(), source: source.id, sourceIn: 0, sourceOut: source.duration, look: look)
        main.append(clip)
        return clip
    }
}

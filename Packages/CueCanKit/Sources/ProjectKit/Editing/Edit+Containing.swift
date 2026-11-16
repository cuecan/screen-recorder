import Foundation

extension Edit {
    /// The main clip a hold sits in: the first that plays part of the held stretch of its recording.
    /// Nil when no clip plays it any more.
    public func clip(holding freeze: Freeze) -> Clip? {
        main.first { clip in
            clip.source == freeze.source
                && clip.playedRange.start < freeze.range.end
                && freeze.range.start < clip.playedRange.end
        }
    }

    /// A clip's place on the main timeline, counting from 1, as the inspector names it ("Clip 2").
    public func position(of clip: ClipID) -> Int? {
        main.firstIndex { $0.id == clip }.map { $0 + 1 }
    }
}

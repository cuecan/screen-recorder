import Foundation

extension Edit {
    /// Sets a clip's layout. The layout its take was set up with becomes Automatic. One layout a clip, drawn
    /// for whichever shape is shown (docs/decisions.md, 77).
    public mutating func setLayout(_ layout: Layout, for id: ClipID, recorded: TakeLayout?) throws(EditError) {
        guard let index = main.firstIndex(where: { $0.id == id }) else { throw .unknownClip(id) }
        main[index].layout = layout == recorded?.layout ? .automatic : layout
    }
}

extension Edit {
    /// Changes a clip's camera side or captions. Each clip's change starts from its own look, so several
    /// clips with different looks can take one change together (docs/decisions.md, 68).
    public mutating func changeLook(for id: ClipID, _ change: (inout ClipLook) -> Void) throws(EditError) {
        guard let index = main.firstIndex(where: { $0.id == id }) else { throw .unknownClip(id) }
        change(&main[index].look)
    }
}

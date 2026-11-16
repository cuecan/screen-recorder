import ProjectKit

extension EditorModel {
    /// The clip inspector's shared caption timing, saved as one change in History.
    func setCaptions(_ reason: String, _ body: @escaping (inout Captions) -> Void) {
        change(reason) { edit, _ in body(&edit.captions) }
    }
}

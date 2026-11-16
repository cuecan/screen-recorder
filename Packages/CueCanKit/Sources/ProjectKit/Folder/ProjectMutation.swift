import Foundation

/// A durable intent for a change spanning several files. Each case carries everything needed to finish
/// the change after an interrupted write; replay is idempotent under the project lock. The journal is
/// internal, and does not change project.json, edit.json, transcript or history formats.
enum ProjectMutation: Codable {
    /// Edit, undo and redo commit their history and redo stack as one recoverable transition.
    case history(edit: Edit, action: HistoryAction, redo: [RedoStack.Entry])

    enum HistoryAction: Codable {
        case append(EditHistory.Entry)
        case undo(through: Int)
    }

    case transcript(project: Project, transcript: Transcript)
}

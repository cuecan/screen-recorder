import Foundation
import ProjectKit
import RenderKit

/// Disk-backed state prepared away from the UI thread before an editor refresh is published.
struct EditorSnapshot: Sendable {
    let inputs: RenderInputs
    let history: [EditHistory.Entry]
    let canRedo: Bool

    nonisolated static func load(_ folder: ProjectFolder) throws -> EditorSnapshot {
        var tries = 0
        while true {
            tries += 1
            let inputs = try RenderInputs.load(folder, keepingEarlierCleaning: true)
            // History is shared with the command-line editor too, so it's read under the project's lock,
            // never halfway through an undo. Only the files are read there: decoding every snapshot takes
            // far longer, and the next change, here or from the command line, waits for that lock.
            let (stored, canRedo, revision) = try folder.withLock {
                ((try? folder.history.storedEntries()) ?? [], folder.canRedo, try? folder.loadEdit().revision)
            }
            // The edit was read before the lock was taken. If a change landed in between, the history is
            // a step ahead of it, so read again. After a few tries a busy project is taken as it is: the
            // next reload catches up.
            if let revision, revision != inputs.edit.revision, tries < 3 { continue }
            let history = (try? stored.map { try EditHistory.entry(decoding: $0) }) ?? []
            return EditorSnapshot(inputs: inputs, history: history, canRedo: canRedo)
        }
    }
}

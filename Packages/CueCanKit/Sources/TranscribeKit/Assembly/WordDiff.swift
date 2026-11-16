import Foundation

/// Where two readings of the same words differ: the runs of words that changed, with what they became.
///
/// It's used to carry a vocabulary correction back onto timed words, and to show what a correction changed.
public enum WordDiff {
    /// One run of changed words.
    public struct Change: Sendable, Equatable {
        /// The changed words' positions in the old reading. Empty when words were only added.
        public var old: Range<Int>
        /// Their positions in the new reading. Empty when words were only removed.
        public var new: Range<Int>

        public init(old: Range<Int>, new: Range<Int>) {
            self.old = old
            self.new = new
        }
    }

    /// The runs that changed from `old` to `new`, in order. Words outside them are the same in both.
    public static func changes(from old: [String], to new: [String]) -> [Change] {
        let difference = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var changes: [Change] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, newIndex < new.count, !removed.contains(oldIndex), !inserted.contains(newIndex) {
                oldIndex += 1
                newIndex += 1
                continue
            }
            let oldStart = oldIndex
            let newStart = newIndex
            while oldIndex < old.count, removed.contains(oldIndex) { oldIndex += 1 }
            while newIndex < new.count, inserted.contains(newIndex) { newIndex += 1 }
            changes.append(Change(old: oldStart..<oldIndex, new: newStart..<newIndex))
        }
        return changes
    }
}

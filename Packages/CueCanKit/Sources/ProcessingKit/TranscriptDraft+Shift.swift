import Foundation
import ProjectKit

extension TranscriptDraft {
    /// The draft moved later by `offset` seconds: from a track's own file time into its source's time.
    func shifted(by offset: TimeInterval) -> TranscriptDraft {
        guard offset != 0 else { return self }
        var draft = self
        draft.items = items.map { item in
            switch item {
            case .word(var word):
                word.start += offset
                word.end += offset
                return .word(word)
            case .silence(let start, let end):
                return .silence(start: start + offset, end: end + offset)
            }
        }
        draft.audioDuration += offset
        return draft
    }
}

import Foundation

/// Why an edit couldn't be made. The messages are read by Claude and shown to creators, so they say what's
/// wrong in plain words and what to do instead.
public enum EditError: Error, Equatable, Sendable, LocalizedError {
    case unknownItem(TranscriptItemID)
    case rangeOutOfOrder(ItemRange)
    case rangeSpansSources(ItemRange)
    case unknownSource(SourceID)
    case noTranscript(SourceID)
    case unknownClip(ClipID)
    case invalidPosition(Int, clipCount: Int)
    case invalidSilenceSettings
    case nudgeLeavesTooLittle(ClipID)
    case nudgeOutsideRecording(ClipID)
    case splitOutsideClip(WordID, ClipID)
    case timeOutsideEdit(TimeInterval, duration: TimeInterval)
    case splitTooCloseToEdge(TimeInterval, ClipID)
    case edgeOutsideRecording(ClipID)
    case edgeLeavesTooLittle(ClipID)
    case unknownOverlay(ClipID)
    case unknownFreeze(FreezeID)
    case invalidTimeRange(TimeRange)
    case noScreenOrCamera
    case wordsNotWords(ItemRange)
    case emptyFix(ItemRange)
    case invalidSpeed(Double)

    public var errorDescription: String? {
        switch self {
        case .unknownItem(let id):
            "There's no \(id) in any transcript in this project. Check the id in get_transcript."
        case .rangeOutOfOrder(let range):
            "\(range.first) comes after \(range.last) in the transcript. Give the earlier id first."
        case .rangeSpansSources(let range):
            "\(range.first) and \(range.last) are in different sources' transcripts. A range has to stay in one source."
        case .unknownSource(let id):
            "There's no source \(id) in this project."
        case .noTranscript(let id):
            "Source \(id) isn't transcribed yet, so it can't be cut by word."
        case .unknownClip(let id):
            "There's no clip \(id) on the timeline."
        case .invalidPosition(let position, let clipCount):
            "Position \(position) isn't on the timeline, which has \(clipCount) clips. Use 0 to \(clipCount)."
        case .invalidSilenceSettings:
            "The pause length to remove has to be longer than the air to leave, and both have to be positive."
        case .nudgeLeavesTooLittle(let id):
            "That nudge would leave clip \(id) almost nothing to play."
        case .nudgeOutsideRecording(let id):
            "That nudge would take clip \(id) past the start or end of its recording."
        case .splitOutsideClip(let word, let clip):
            "\(word) isn't inside clip \(clip), so the clip can't be split there. Split before a word the clip plays, other than its first."
        case .timeOutsideEdit(let time, let duration):
            "\(String(format: "%.2f", time)) s isn't on the edited timeline, which runs from 0 to \(String(format: "%.2f", duration)) s."
        case .splitTooCloseToEdge(let time, let clip):
            "\(String(format: "%.2f", time)) s is at the edge of clip \(clip), so there's nothing to split. Split somewhere inside it."
        case .edgeOutsideRecording(let id):
            "That would take clip \(id) past the start or end of its recording."
        case .edgeLeavesTooLittle(let id):
            "That would leave clip \(id) almost nothing to play. To remove it, cut it."
        case .unknownOverlay(let id):
            "There's no overlay \(id) in the edit."
        case .unknownFreeze(let id):
            "There's no freeze \(id) in the edit."
        case .invalidTimeRange(let range):
            "A time range has to end after it starts, and \(range) doesn't."
        case .noScreenOrCamera:
            "That part of the edit has no picture to hold."
        case .wordsNotWords(let range):
            "\(range) has to start and end on words, not pauses."
        case .emptyFix(let range):
            "A fix needs words. To take \(range) out of the video, cut it."
        case .invalidSpeed(let rate):
            "A clip plays at 1, 1.5, 2, 4 or 8 times speed, not \(rate)."
        }
    }
}

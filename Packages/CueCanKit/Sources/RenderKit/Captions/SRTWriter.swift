import Foundation

/// Writes captions as SubRip (`.srt`), the file YouTube takes and Resolve and Final Cut import.
public enum SRTWriter {
    public static func srt(_ cues: [CaptionCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.timeline.start)) --> \(timestamp(cue.timeline.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    /// `HH:MM:SS,mmm`.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = milliseconds / 60_000 % 60
        let secs = milliseconds / 1000 % 60
        let millis = milliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

/// Writes the edit's words as plain text, for YouTube's transcript or another editor: the captions' words in
/// order, a new paragraph wherever the speaker paused for a while.
public enum TextTranscriptWriter {
    /// A gap between captions at least this long starts a new paragraph. A starting value.
    public static let paragraphBreak: TimeInterval = 2

    public static func text(_ cues: [CaptionCue]) -> String {
        var paragraphs: [[String]] = []
        var previousEnd: TimeInterval?
        for cue in cues {
            if let end = previousEnd, cue.timeline.start - end < paragraphBreak, !paragraphs.isEmpty {
                paragraphs[paragraphs.count - 1].append(cue.text)
            } else {
                paragraphs.append([cue.text])
            }
            previousEnd = cue.timeline.end
        }
        return paragraphs.map { $0.joined(separator: " ") }.joined(separator: "\n\n") + (paragraphs.isEmpty ? "" : "\n")
    }
}

import Foundation
import ProjectKit

/// A transcript as compact text, one item per line, which is far shorter for Claude to read than JSON:
///
///     + w_12  12.34–12.80  Hello
///       s_4   12.80–14.10  (pause 1.30 s)
///     + w_13  14.10–14.42  um  [filler]
///       w_14  14.42–14.90  Q  {SpeechAnalyzer heard “CueCan” for w_14…w_15}
///
/// `+` marks what the edit plays.
enum TranscriptText {
    static let legend = """
        Each line is an id, its start and end in seconds of source time, and the word, or a pause.
        + marks what the edit plays. [filler] marks a filler word.
        {SpeechAnalyzer heard “…” for w_a…w_b} is Apple's second reading where it differs: often right on clean speech and names; Parakeet's words keep the stumbles. Use it for spelling; cut by Parakeet's ids.
        {spelled “…” for w_a…w_b} is a vocabulary term swapped in over those words.
        """

    static func text(
        _ transcript: Transcript,
        source: Source,
        used: Set<TranscriptItemID>,
        spellings: VocabularySpellings?
    ) -> String {
        var notes: [TranscriptItemID: [String]] = [:]
        for alternative in transcript.alternatives {
            let words = alternative.words.first == alternative.words.last ? "\(alternative.words.first)" : alternative.words.description
            notes[alternative.words.first, default: []].append("{SpeechAnalyzer heard “\(alternative.text)” for \(words)}")
        }
        for spelling in spellings?.spellings ?? [] {
            notes[spelling.words.first, default: []].append("{spelled “\(spelling.text)” for \(spelling.words)}")
        }

        var lines = ["\(source.id) · \(source.name) · \(format(transcript.audioDuration)) s · \(transcript.words.count) words"]
        for item in transcript.items {
            let marker = used.contains(item.id) ? "+" : " "
            let id = "\(item.id)".padding(toLength: 7, withPad: " ", startingAt: 0)
            let times = "\(format(item.start))–\(format(item.end))"
            var line: String
            switch item {
            case .word(let word):
                line = "\(marker) \(id) \(times)  \(word.text)"
                if word.isFiller { line += "  [filler]" }
            case .silence(let silence):
                line = "\(marker) \(id) \(times)  (pause \(format(silence.duration)) s)"
            }
            if let extra = notes[item.id] { line += "  " + extra.joined(separator: " ") }
            lines.append(line)
        }
        for retake in transcript.retakes {
            lines.append("Retake: \(retake.attempt) looks like an earlier try at \(retake.redoneAs)")
        }
        return lines.joined(separator: "\n")
    }

    static func format(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }
}

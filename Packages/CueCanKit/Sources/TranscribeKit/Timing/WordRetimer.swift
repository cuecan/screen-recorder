import Foundation

/// Puts new start times on a transcript's words and keeps the words a transcript can be built from: in
/// order, none starting before the one before it, none ending before it starts or after the next begins.
///
/// The words are Parakeet's; the starts come from the timing model (``WordTimer``; docs/decisions.md, 95).
/// The model gives no usable end: it marks where it recognised a word's last piece, which on a real voice was
/// about 180 ms before the sound stopped (docs/bakeoff-findings.md). So a word that ran straight into the
/// next still does, ending where the next now starts, and a word with a gap after it keeps its own end,
/// which ``WordFitter`` then trims to the silence the audio shows.
public enum WordRetimer {
    /// Two words closer than this ran together in the original times.
    public static let touching: TimeInterval = 0.02
    /// No word is made shorter than this.
    public static let shortestWord: TimeInterval = 0.04

    /// - Parameters:
    ///   - words: The transcript's words, in order.
    ///   - starts: A new start for each word, or nil to keep its own. Same count as `words`.
    public static func retime(_ words: [TimedWord], starts: [TimeInterval?]) -> [TimedWord] {
        guard words.count == starts.count, !words.isEmpty else { return words }
        var newStarts: [TimeInterval] = []
        var floor: TimeInterval = 0
        for (word, start) in zip(words, starts) {
            let chosen = max(floor, start ?? word.start)
            newStarts.append(chosen)
            floor = chosen
        }
        var result = words
        for index in words.indices {
            let start = newStarts[index]
            let next = index + 1 < words.count ? newStarts[index + 1] : nil
            var end: TimeInterval
            if let next, words[index + 1].start - words[index].end <= touching {
                end = next
            } else {
                // Its own end, moved with it when the word moved later than it used to end.
                end = max(words[index].end, start + shortestWord)
                if let next { end = min(end, next) }
            }
            result[index].start = start
            result[index].end = max(start, end)
        }
        return result
    }
}

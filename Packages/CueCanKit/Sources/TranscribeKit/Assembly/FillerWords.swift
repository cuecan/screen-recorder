import Foundation

/// Recognizes filler words, which are marked in the transcript for Claude to decide on.
///
/// Only sounds that are fillers whatever the context are listed. Words like "like" or "so" are fillers
/// only sometimes, so they're left for Claude to judge from the sentence.
public enum FillerWords {
    public static let english: Set<String> = [
        "um", "umm", "uhm", "uh", "uhh", "erm", "er", "ah", "hmm", "hm", "mm", "mhm",
    ]

    public static func isFiller(_ text: String) -> Bool {
        let normalized = text.lowercased().filter { $0.isLetter }
        return english.contains(normalized)
    }
}

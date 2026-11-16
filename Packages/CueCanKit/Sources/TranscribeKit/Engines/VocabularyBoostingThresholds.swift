import Foundation

/// How readily vocabulary boosting swaps a heard word for a listed term (``ParakeetEngine``).
///
/// FluidAudio's own defaults favour catching every term. In an editor a wrong swap costs more than a miss: it
/// puts a word in the transcript that wasn't said, which Claude then cuts by. On real recordings FluidAudio's
/// defaults swapped "password" for "passwordless", "level" for "Laravel" and "fiscal CLI" for "Final Cut".
/// The defaults here made none of those, and kept most of the right swaps (docs/bakeoff-findings.md,
/// "Vocabulary boosting"). They're from four recordings, so they're a starting point (TEST NEEDED).
public struct VocabularyBoostingThresholds: Sendable, Equatable, Codable {
    /// The head start a term gets over the heard words when the two are scored against the audio. 0 means a
    /// term has to fit the audio better on its own; FluidAudio's default is 4.5. At 0 a swap dropped a real
    /// word ("level, pass keys" became "passkeys").
    public var termBonus: Double
    /// How closely a heard word has to be spelled like a term to be considered for a swap, from 0 to 1.
    /// FluidAudio's default is 0.5 to 0.6, by vocabulary size.
    public var minimumSimilarity: Double

    public init(termBonus: Double = 2, minimumSimilarity: Double = 0.6) {
        self.termBonus = termBonus
        self.minimumSimilarity = minimumSimilarity
    }
}

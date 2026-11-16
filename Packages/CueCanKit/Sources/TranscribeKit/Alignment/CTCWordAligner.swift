import AudioKit
internal import FluidAudio
import Foundation
import ProjectKit

/// Times a fix against the audio (docs/decisions.md, 69): FluidAudio's Parakeet CTC 110M, the model
/// vocabulary boosting already uses, gives each frame's token probabilities, and ``ForcedAligner`` finds
/// when each word of the fix was said.
///
/// FluidAudio has no alignment call of its own; this uses only its public pieces: the keyword spotter's
/// log-probabilities and frame duration, and the CTC tokenizer. Keep one aligner for several fixes, so the
/// model loads once.
public final class CTCWordAligner {
    /// What came back from timing a fix.
    public struct Result: Equatable, Sendable {
        /// Each word of the fix with its times, in source time.
        public var words: [AlignedWord]
        /// Each word's confidence, from 0 to 1: the average probability of its tokens on the frames they hold.
        public var confidences: [Double]
        /// Each word's gap below what the model heard best (``ForcedAligner/Placement/gap``).
        public var gaps: [Double]
        /// Whether some of the words matched the audio well enough to use their times: their average gap is
        /// within ``maximumGap``.
        public func matches(_ words: Range<Int>) -> Bool {
            guard !words.isEmpty, words.lowerBound >= 0, words.upperBound <= gaps.count else { return false }
            return gaps[words].reduce(0, +) / Double(words.count) <= CTCWordAligner.maximumGap
        }
    }

    /// The largest average gap (``ForcedAligner/Placement/gap``) a fix's times are used at. Above it the text
    /// probably isn't what was said, and the fix stays untimed.
    ///
    /// Measured on two of real takes, aligned with the
    /// words around them: fixes that were said averaged 0 to 5.7 ("That all looks", on mumbled speech, was
    /// 5.7), and text that wasn't said averaged 7.6 ("Purple monkey dishwasher") and 8.8 ("Banana pancakes").
    /// The per-word confidence didn't separate them: words that were said scored 0.000 in one window and
    /// 0.5 in another. TEST NEEDED on more takes: two takes are not a measure, and the margin is thin.
    public static let maximumGap = 6.5

    /// How many seconds of the words either side a fix is aligned with. The model reads a word better with
    /// some of what was said around it.
    public static let context: TimeInterval = 3

    /// How much audio before the first word and after the last is aligned, in seconds, so their edges can
    /// move: words heard wrong may have their edges wrong too.
    public static let padding: TimeInterval = 0.3

    /// Both resources must load successfully before the model can be used or cached.
    private struct Models {
        let spotter: CtcKeywordSpotter
        let tokenizer: CtcTokenizer
    }
    private enum State { case unloaded, ready(Models) }
    private var state = State.unloaded

    public init() {}

    /// Loads the model, downloading it the first time.
    public func load() async throws {
        guard case .unloaded = state else { return }
        do {
            let models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
            let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
            let tokenizer = try await CtcTokenizer.load()
            state = .ready(Models(spotter: spotter, tokenizer: tokenizer))
        } catch {
            throw AudioKitError.modelFailed("Parakeet CTC", "Couldn't load the model that times fixes: \(error.localizedDescription)")
        }
    }

    /// Times `text` within a stretch of audio. Nil when the text can't be placed in it at all.
    ///
    /// - Parameters:
    ///   - audio: The stretch of audio, any sample rate.
    ///   - startsAt: Where the stretch starts, in source time, which the result's times are in.
    public func align(_ text: String, in audio: AudioSamples, startsAt: TimeInterval) async throws -> Result? {
        try await load()
        guard case .ready(let models) = state else { return nil }
        let spotter = models.spotter, tokenizer = models.tokenizer
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let samples = try audio.resampled(to: 16_000).samples
        let output = try await spotter.spotKeywordsWithLogProbs(audioSamples: samples, customVocabulary: CustomVocabularyContext(terms: []))
        guard output.frameDuration > 0,
              let placements = ForcedAligner.align(logProbabilities: output.logProbs, words: words.map(tokenizer.encode), blank: spotter.blankId)
        else { return nil }
        let aligned = zip(words, placements).map { word, placement in
            AlignedWord(text: word,
                        start: startsAt + Double(placement.frames.lowerBound) * output.frameDuration,
                        end: startsAt + Double(placement.frames.upperBound) * output.frameDuration)
        }
        return Result(words: aligned, confidences: placements.map(\.confidence), gaps: placements.map(\.gap))
    }
}

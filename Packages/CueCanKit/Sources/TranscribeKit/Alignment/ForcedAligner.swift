import Foundation

/// CTC forced alignment: given a CTC model's log-probabilities for some audio and text known to be what was
/// said, finds when each word was said (docs/decisions.md, 69).
///
/// The best path through the text's tokens, with a blank allowed between and around them, is found by
/// Viterbi. Each word runs from its first token's first frame to its last token's last frame. This is pure
/// arithmetic on the probabilities, so it's tested on made-up ones; ``CTCWordAligner`` runs it on the model.
public enum ForcedAligner {
    /// One word placed in the frames.
    public struct Placement: Equatable, Sendable {
        /// The first frame and the frame after the last, of the word's tokens.
        public var frames: Range<Int>
        /// The average probability, from 0 to 1, of the word's tokens on the frames they hold.
        public var confidence: Double
        /// How far the path falls below the model's own likeliest token, per frame over the word, in natural
        /// log units: near 0 where the model heard these words, large where it heard something else.
        public var gap: Double
    }

    /// The best path's placement of each word, or nil when the words can't fit in the frames.
    ///
    /// - Parameters:
    ///   - logProbabilities: Per frame, the log-probability of each token, blank included.
    ///   - words: Each word's token ids, in order. A word with no tokens can't be placed.
    ///   - blank: The blank token's id.
    public static func align(logProbabilities: [[Float]], words: [[Int]], blank: Int) -> [Placement]? {
        let tokens = words.flatMap { $0 }
        guard blank >= 0, !tokens.isEmpty, words.allSatisfy({ !$0.isEmpty }),
              tokens.allSatisfy({ $0 >= 0 && $0 != blank }) else { return nil }
        let frameCount = logProbabilities.count
        // The states: blank, token 1, blank, token 2, …, blank.
        let states = 2 * tokens.count + 1
        func token(atState state: Int) -> Int { state.isMultiple(of: 2) ? blank : tokens[state / 2] }
        func logProbability(_ frame: Int, _ state: Int) -> Float {
            let row = logProbabilities[frame]
            let id = token(atState: state)
            return id < row.count ? row[id] : -.infinity
        }
        guard frameCount > 0 else { return nil }

        var score = [Float](repeating: -.infinity, count: states)
        // Where each state's best path came from, per frame: 0 itself, 1 the state before, 2 two before.
        var steps = [[UInt8]](repeating: [UInt8](repeating: 0, count: states), count: frameCount)
        score[0] = logProbability(0, 0)
        if states > 1 { score[1] = logProbability(0, 1) }
        for frame in 1..<max(1, frameCount) {
            var next = [Float](repeating: -.infinity, count: states)
            for state in 0..<states {
                var best = score[state]
                var step: UInt8 = 0
                if state >= 1, score[state - 1] > best {
                    best = score[state - 1]
                    step = 1
                }
                // A token can follow the token before it directly, skipping the blank, unless it's the same
                // token: then a blank has to come between, or the two would read as one.
                if state >= 2, !state.isMultiple(of: 2), token(atState: state) != token(atState: state - 2), score[state - 2] > best {
                    best = score[state - 2]
                    step = 2
                }
                guard best > -.infinity else { continue }
                next[state] = best + logProbability(frame, state)
                steps[frame][state] = step
            }
            score = next
        }
        // The path ends on the last token or the blank after it.
        var state = states - 1
        if states >= 2, score[states - 2] > score[states - 1] { state = states - 2 }
        guard score[state] > -.infinity else { return nil }

        // Back through the frames, noting which token holds each one, and how far below the frame's likeliest
        // token the path is there.
        var tokenOfFrame = [Int?](repeating: nil, count: frameCount)
        var shortfall = [Double](repeating: 0, count: frameCount)
        for frame in stride(from: frameCount - 1, through: 0, by: -1) {
            if !state.isMultiple(of: 2) { tokenOfFrame[frame] = state / 2 }
            let best = logProbabilities[frame].max() ?? 0
            shortfall[frame] = Double(best - logProbability(frame, state))
            if frame > 0 { state -= Int(steps[frame][state]) }
        }

        var placements: [Placement] = []
        var firstToken = 0
        for word in words {
            let wordTokens = firstToken..<(firstToken + word.count)
            firstToken += word.count
            let frames = tokenOfFrame.indices.filter { tokenOfFrame[$0].map(wordTokens.contains) ?? false }
            guard let start = frames.first, let end = frames.last else { return nil }
            let probabilities = frames.compactMap { frame in tokenOfFrame[frame].map { Double(exp(logProbabilities[frame][tokens[$0]])) } }
            let gap = shortfall[start...end].reduce(0, +) / Double(end - start + 1)
            placements.append(Placement(frames: start..<(end + 1), confidence: probabilities.reduce(0, +) / Double(probabilities.count), gap: gap))
        }
        return placements
    }
}

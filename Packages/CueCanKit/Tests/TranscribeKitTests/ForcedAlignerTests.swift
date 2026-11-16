import Foundation
import Testing
import AudioKit
import ProjectKit
@testable import TranscribeKit

/// Forced alignment on made-up probabilities (docs/decisions.md, 69): which token each frame most likely
/// holds is set by hand, so where each word lands is known.
struct ForcedAlignerTests {
    static let blank = 4

    /// Frames whose likeliest token is the given one, at probability 0.9, the rest sharing what's left.
    static func frames(_ likeliest: [Int]) -> [[Float]] {
        likeliest.map { best in (0...blank).map { $0 == best ? log(0.9) : log(0.1 / Float(blank)) } }
    }

    @Test func eachWordRunsFromItsFirstTokenToItsLast() throws {
        let b = Self.blank
        let placements = try #require(ForcedAligner.align(logProbabilities: Self.frames([b, b, 1, 1, b, 2, 2, 3, b, b]),
                                                          words: [[1], [2, 3]], blank: b))
        #expect(placements.map(\.frames) == [2..<4, 5..<8])
        #expect(placements.allSatisfy { abs($0.confidence - 0.9) < 0.0001 })
        #expect(placements.allSatisfy { $0.gap < 0.0001 }, "The path is the model's own best guess.")
    }

    @Test func aRepeatedTokenNeedsABlankBetween() throws {
        let b = Self.blank
        // "1 1" with no blank between would read as one token, so the path has to find the blank.
        let placements = try #require(ForcedAligner.align(logProbabilities: Self.frames([1, 1, b, 1, b]), words: [[1], [1]], blank: b))
        #expect(placements.map(\.frames) == [0..<2, 3..<4])
    }

    @Test func textThatWasntSaidHasLowConfidence() throws {
        let b = Self.blank
        let placements = try #require(ForcedAligner.align(logProbabilities: Self.frames([b, 1, 1, b]), words: [[2]], blank: b))
        #expect(placements[0].confidence < 0.1)
        #expect(placements[0].gap > 2, "The path falls far below what the model heard.")
    }

    @Test func wordsThatDontFitAreNotPlaced() {
        let b = Self.blank
        #expect(ForcedAligner.align(logProbabilities: Self.frames([1, 1]), words: [[1], [1]], blank: b) == nil, "Two 1s need three frames.")
        #expect(ForcedAligner.align(logProbabilities: [], words: [[1]], blank: b) == nil)
        #expect(ForcedAligner.align(logProbabilities: Self.frames([1]), words: [[]], blank: b) == nil)
    }

    @Test func invalidTokenIdsAndScoreRangesAreRejected() {
        let frames = Self.frames([1, 1, Self.blank])
        #expect(ForcedAligner.align(logProbabilities: frames, words: [[-1]], blank: Self.blank) == nil)
        #expect(ForcedAligner.align(logProbabilities: frames, words: [[Self.blank]], blank: Self.blank) == nil)
        #expect(ForcedAligner.align(logProbabilities: frames, words: [[1]], blank: -1) == nil)
        #expect(ForcedAligner.align(logProbabilities: frames, words: [[999]], blank: Self.blank) == nil)
        let result = CTCWordAligner.Result(words: [], confidences: [], gaps: [1, 2])
        #expect(!result.matches(-1..<1))
        #expect(!result.matches(1..<3))
        #expect(result.matches(0..<2))
    }
}

/// Timing a fix on a real recording, by hand: set `CUECAN_ALIGN_AUDIO` to a mic file, `CUECAN_ALIGN_RANGE`
/// to "start-end" in seconds and `CUECAN_ALIGN_TEXT` to what was said there. It prints what it found. Never
/// run on its own, since it loads the model; it's for checking alignment on real takes (TEST NEEDED).
struct RealRecordingAlignment {
    static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["CUECAN_ALIGN_AUDIO"] != nil))
    func alignsAFixOnARecording() async throws {
        let url = URL(filePath: try #require(Self.environment["CUECAN_ALIGN_AUDIO"]))
        let bounds = try #require(Self.environment["CUECAN_ALIGN_RANGE"]).split(separator: "-").compactMap { Double($0) }
        let text = try #require(Self.environment["CUECAN_ALIGN_TEXT"])
        let range = TimeRange(start: bounds[0], end: bounds[1])
        let audio = try await AudioFileReader.readMono(url, sampleRate: 16_000, timeRange: range)
        let result = try await CTCWordAligner().align(text, in: audio, startsAt: range.start)
        print("ALIGNED", result.map { "\($0.words.map { "\($0.text) \(String(format: "%.2f–%.2f", $0.start, $0.end))" }) confidences \($0.confidences.map { String(format: "%.3f", $0) }) gaps \($0.gaps.map { String(format: "%.2f", $0) })" } ?? "nothing")
    }
}

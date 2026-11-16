import Foundation
@testable import ProjectKit

/// Builds transcripts from a compact description, numbering ids from a starting point.
struct TranscriptBuilder {
    enum Piece {
        case word(String, TimeInterval, TimeInterval, filler: Bool = false)
        case silence(TimeInterval, TimeInterval)
    }

    static func make(
        source: SourceID,
        duration: TimeInterval,
        firstWord: Int = 1,
        firstSilence: Int = 1,
        _ pieces: [Piece]
    ) -> Transcript {
        let draft = TranscriptDraft(
            engine: "test",
            silenceDetector: "test",
            language: "en",
            audioDuration: duration,
            items: pieces.map { piece in
                switch piece {
                case .word(let text, let start, let end, let filler):
                    .word(.init(text: text, start: start, end: end, isFiller: filler))
                case .silence(let start, let end):
                    .silence(start: start, end: end)
                }
            }
        )
        return draft.assigningIDs(
            source: source,
            firstWordNumber: firstWord,
            firstSilenceNumber: firstSilence,
            createdAt: Date(timeIntervalSince1970: 0)
        ).transcript
    }
}

/// "Hello there. [pause] Um, this is the take. [pause] This is the take."
///
///     s_1  0.00–1.00   silence
///     w_1  1.00–1.40   Hello
///     w_2  1.45–1.80   there.
///     s_2  1.80–2.60   silence
///     w_3  2.60–2.90   Um,        filler
///     s_3  2.90–3.00   silence    (shorter than the two pads)
///     w_4  3.00–3.30   this
///     w_5  3.30–3.50   is
///     w_6  3.50–3.70   the
///     w_7  3.70–4.10   take.
///     s_4  4.10–5.60   silence    (a long pause)
///     w_8  5.60–5.90   This
///     w_9  5.90–6.10   is
///     w_10 6.10–6.30   the
///     w_11 6.30–6.70   take.
///     s_5  6.70–7.00   silence
let talkingHead = TranscriptBuilder.make(
    source: SourceID(number: 1),
    duration: 7.0,
    [
        .silence(0.0, 1.0),
        .word("Hello", 1.0, 1.4),
        .word("there.", 1.45, 1.8),
        .silence(1.8, 2.6),
        .word("Um,", 2.6, 2.9, filler: true),
        .silence(2.9, 3.0),
        .word("this", 3.0, 3.3),
        .word("is", 3.3, 3.5),
        .word("the", 3.5, 3.7),
        .word("take.", 3.7, 4.1),
        .silence(4.1, 5.6),
        .word("This", 5.6, 5.9),
        .word("is", 5.9, 6.1),
        .word("the", 6.1, 6.3),
        .word("take.", 6.3, 6.7),
        .silence(6.7, 7.0),
    ]
)

/// A second source, numbered on from the first, as `ProjectFolder.addTranscript` would number it.
let secondAngle = TranscriptBuilder.make(
    source: SourceID(number: 2),
    duration: 3.0,
    firstWord: 12,
    firstSilence: 6,
    [
        .silence(0.0, 0.5),
        .word("Second", 0.5, 1.0),
        .word("source.", 1.0, 1.6),
        .silence(1.6, 3.0),
    ]
)

func w(_ number: Int) -> TranscriptItemID { .word(WordID(number: number)) }
func s(_ number: Int) -> TranscriptItemID { .silence(SilenceID(number: number)) }
func range(_ first: TranscriptItemID, _ last: TranscriptItemID) -> ItemRange { ItemRange(first: first, last: last) }

/// Pads that make the arithmetic in tests easy to follow.
let testPads = SnapSettings(leadPad: 0.05, trailPad: 0.1)

/// Where both edges of `talkingHead`'s short pause (s_3, 2.9–3.0) meet with `testPads`: it's shorter than
/// the two pads together, so it's split in their ratio, two thirds to "Um," before it. About 2.967.
let shortPauseEdge = 2.9 + (3.0 - 2.9) * testPads.trailPad / (testPads.leadPad + testPads.trailPad)

/// A fresh empty folder in the temporary directory.
func makeTemporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "ProjectKitTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension Double {
    /// Equal to within a microsecond, for comparing computed times.
    func isClose(to other: Double, tolerance: Double = 1e-6) -> Bool {
        abs(self - other) <= tolerance
    }
}

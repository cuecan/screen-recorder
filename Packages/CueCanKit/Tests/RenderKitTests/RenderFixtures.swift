import CoreGraphics
import Foundation
import ProjectKit

/// A transcript from (text, start, end) words and (start, end) silences, in order.
enum Piece {
    case word(String, TimeInterval, TimeInterval, filler: Bool = false)
    case silence(TimeInterval, TimeInterval)
}

func makeTranscript(source: Int = 1, duration: TimeInterval, firstWord: Int = 1, _ pieces: [Piece]) -> Transcript {
    let draft = TranscriptDraft(
        engine: "test",
        silenceDetector: "test",
        language: "en",
        audioDuration: duration,
        items: pieces.map { piece in
            switch piece {
            case .word(let text, let start, let end, let filler): .word(.init(text: text, start: start, end: end, isFiller: filler))
            case .silence(let start, let end): .silence(start: start, end: end)
            }
        }
    )
    return draft.assigningIDs(source: SourceID(number: source), firstWordNumber: firstWord, firstSilenceNumber: firstWord).transcript
}

/// "Hello there. Um, this is the take." with pauses: w_1…w_7.
let speech = makeTranscript(
    duration: 6,
    [
        .silence(0, 1),
        .word("Hello", 1.0, 1.4), .word("there.", 1.45, 1.8),
        .silence(1.8, 2.6),
        .word("Um,", 2.6, 2.9, filler: true),
        .silence(2.9, 3.0),
        .word("this", 3.0, 3.3), .word("is", 3.3, 3.5), .word("the", 3.5, 3.7), .word("take.", 3.7, 4.1),
        .silence(4.1, 6),
    ]
)

func clip(_ number: Int, source: Int = 1, _ start: TimeInterval, _ end: TimeInterval, layout: Layout = .automatic) -> Clip {
    Clip(id: ClipID(number: number), source: SourceID(number: source), sourceIn: start, sourceOut: end, layout: layout)
}

func w(_ number: Int) -> TranscriptItemID { .word(WordID(number: number)) }

extension CGRect {
    func isClose(to other: CGRect, within tolerance: Double = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

extension Double {
    func isClose(to other: Double, within tolerance: Double = 1e-6) -> Bool { abs(self - other) <= tolerance }
}

extension CGFloat {
    func isClose(to other: Double, within tolerance: Double = 1e-6) -> Bool { abs(Double(self) - other) <= tolerance }
}

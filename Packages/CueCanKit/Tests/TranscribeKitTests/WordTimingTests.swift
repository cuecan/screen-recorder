import Foundation
import Testing
@testable import TranscribeKit

/// Placing Parakeet's words with the timing model (docs/decisions.md, 95): the parts that are plain logic.
struct WordTimingTests {
    private func word(_ text: String, _ start: Double, _ end: Double) -> TimedWord { TimedWord(text: text, start: start, end: end) }

    @Test func wordsThatRanTogetherStillDoAndAWordBeforeAGapKeepsItsEnd() {
        // "so here's" ran together; "here's" was followed by a gap.
        let words = [word("so", 13.04, 13.68), word("here's", 13.68, 14.24), word("just", 14.90, 15.10)]
        let retimed = WordRetimer.retime(words, starts: [13.20, 14.08, 14.96])
        #expect(retimed.map(\.start) == [13.20, 14.08, 14.96])
        #expect(retimed[0].end == 14.08, "It ran into the next word, so it ends where that now starts.")
        #expect(retimed[1].end == 14.24, "A gap followed it, so its own end stays for the fitter to trim.")
        #expect(retimed[2].end == 15.10)
        #expect(retimed.map(\.text) == ["so", "here's", "just"])
    }

    @Test func aWordThatCouldNotBePlacedKeepsItsTimeAndNothingGoesBackwards() {
        let words = [word("a", 1.0, 1.2), word("b", 1.2, 1.5), word("c", 1.5, 1.9), word("d", 2.6, 2.9)]
        // "b" wasn't placed; "c" was placed before "b"'s own time, which can't be.
        let retimed = WordRetimer.retime(words, starts: [1.08, nil, 1.16, 3.2])
        #expect(retimed.map(\.start) == [1.08, 1.2, 1.2, 3.2])
        for (left, right) in zip(retimed, retimed.dropFirst()) { #expect(left.end <= right.start && left.start <= left.end) }
        #expect(retimed[3].end == 3.24, "A word moved past its own end is given the shortest length.")
        #expect(WordRetimer.retime(words, starts: [1, 2]) == words, "A mismatched list changes nothing.")
        #expect(WordRetimer.retime([], starts: []).isEmpty)
    }

    @Test func aShortRecordingIsPlacedInOneStretch() {
        let spans = AlignmentPlan.spans(starts: [0.5, 4, 19], duration: 20.4, window: 30)
        #expect(spans == [.init(windows: 0..<1, words: 0..<3, kept: 0..<3)])
        #expect(AlignmentPlan.spans(starts: [], duration: 20, window: 30).isEmpty)
    }

    @Test func aLongRecordingIsPlacedAWindowAtATimeWithAWindowEitherSide() {
        // A word every 5 s for 100 s: windows 0-30, 30-60, 60-90, 90-100.
        let starts = stride(from: 2.0, to: 100, by: 5).map { $0 }
        let spans = AlignmentPlan.spans(starts: starts, duration: 100, window: 30)
        #expect(spans.map(\.windows) == [0..<2, 0..<3, 1..<4, 2..<4])
        // Every word is kept exactly once, in order.
        #expect(spans.flatMap { Array($0.kept) } == Array(starts.indices))
        for span in spans {
            #expect(span.words.lowerBound <= span.kept.lowerBound && span.kept.upperBound <= span.words.upperBound)
        }
        // The second stretch is 0 to 90 s: it leaves out the words within 1.5 s of its cut at 90 s, and
        // keeps the ones that start between 30 and 60 s.
        #expect(spans[1].words == 0..<18 && spans[1].kept == 6..<12)
        // The third starts at 30 s, so the word at 32 s, past the margin, is in and the one at 27 s isn't.
        #expect(spans[2].words.lowerBound == 6)
    }

    @Test func aWindowWithNoWordsIsSkipped() {
        let spans = AlignmentPlan.spans(starts: [1, 2, 95], duration: 100, window: 30)
        #expect(spans.map(\.kept) == [0..<2, 2..<3])
    }

    @Test func aDownloadIsCheckedByItsDigest() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "cuecan-digest-\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(try TimingModelDownload.digest(of: file) == abc)
        #expect(TimingModelDownload.digest(of: Data("abc".utf8)) == abc)
    }

    @Test func everythingComesFromOnePinnedRevisionOnHuggingFace() {
        let address = TimingModelDownload.address(of: "assets/vocab.json")?.absoluteString
        #expect(address == "https://huggingface.co/FluidInference/nemotron-3.5-transcribe-lite-coreml/resolve/31ecb73ab8a541001c0952802b478384cf9f0691/assets/vocab.json")
        #expect(TimingModelDownload.revision.count == 40)
    }

    @Test func theDescriptionsPatchIsAppliedInOrderAndOnlyWhereItFits() {
        let data = Data("0123456789".utf8)
        let edits = [TimingModelDownload.Edit(offset: 2, drop: 1, put: Array("AB".utf8)),
                     TimingModelDownload.Edit(offset: 5, drop: 2, put: []),
                     TimingModelDownload.Edit(offset: 10, drop: 0, put: Array("!".utf8))]
        #expect(TimingModelDownload.applying(edits, to: data) == Data("01AB3478 9!".replacingOccurrences(of: " ", with: "").utf8))
        #expect(TimingModelDownload.applying([.init(offset: 9, drop: 5, put: [])], to: data) == nil)
        #expect(TimingModelDownload.applying(edits.reversed(), to: data) == nil, "Edits out of order aren't applied.")
        // The real patch: four edits on a file of the published size, growing it by 50 bytes.
        let real = TimingModelDownload.edits
        #expect(real.count == 4 && real.map(\.offset) == real.map(\.offset).sorted())
        #expect(real.reduce(0) { $0 + $1.put.count - $1.drop } == 50)
        #expect(real.last?.offset == TimingModelDownload.descriptionByteCount)
    }

    @Test func aFolderMissingAFileIsNotAnInstalledModel() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "cuecan-timer-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appending(path: "model.mlmodelc"), withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "vocab.json"))
        #expect(!WordTimer.isInstalled(at: folder))
        #expect(throws: (any Error).self) { _ = try WordTimer(directory: folder) }
    }
}

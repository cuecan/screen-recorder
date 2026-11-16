import Foundation
import Testing
@testable import TranscribeKit

@Suite struct WordDiffTests {
    @Test func sameWordsHaveNoChanges() {
        #expect(WordDiff.changes(from: ["a", "b"], to: ["a", "b"]).isEmpty)
    }

    @Test func aMergeIsOneChange() {
        let changes = WordDiff.changes(from: ["sign", "in", "with", "pass", "key", "button"], to: ["sign", "in", "with", "passkey", "button"])
        #expect(changes == [WordDiff.Change(old: 3..<5, new: 3..<4)])
    }

    @Test func separateChangesStaySeparate() {
        let changes = WordDiff.changes(from: ["Swift", "2i", "app", "in", "Laraville"], to: ["SwiftUI", "app", "in", "Laravel"])
        #expect(changes == [WordDiff.Change(old: 0..<2, new: 0..<1), WordDiff.Change(old: 4..<5, new: 3..<4)])
    }

    @Test func additionsAndRemovalsAreChangesWithOneSideEmpty() {
        #expect(WordDiff.changes(from: ["a", "c"], to: ["a", "b", "c"]) == [WordDiff.Change(old: 1..<1, new: 1..<2)])
        #expect(WordDiff.changes(from: ["a", "b", "c"], to: ["a", "c"]) == [WordDiff.Change(old: 1..<2, new: 1..<1)])
    }
}

@Suite struct VocabularyCorrectionTests {
    let words = [
        TimedWord(text: "with", start: 0.0, end: 0.2, confidence: 0.9),
        TimedWord(text: "pass", start: 0.3, end: 0.5, confidence: 0.6),
        TimedWord(text: "key", start: 0.5, end: 0.9, confidence: 0.8),
        TimedWord(text: "in", start: 1.0, end: 1.1, confidence: 0.9),
        TimedWord(text: "Laraville", start: 1.2, end: 1.8, confidence: 0.5),
    ]

    @Test func untouchedTextLeavesTheWordsAlone() {
        #expect(VocabularyCorrection.apply("with pass key in Laraville", to: words) == words)
        #expect(VocabularyCorrection.corrections("with pass key in Laraville", to: words).isEmpty)
    }

    @Test func correctionsNameTheWordsTheyReplace() {
        let corrections = VocabularyCorrection.corrections("with passkey in Laravel", to: words)
        #expect(corrections == [
            VocabularyCorrection.Correction(words: 1..<3, text: "passkey"),
            VocabularyCorrection.Correction(words: 4..<5, text: "Laravel"),
        ])
    }

    @Test func aMergedWordSpansTheWordsItReplaces() throws {
        let corrected = VocabularyCorrection.apply("with passkey in Laravel", to: words)
        #expect(corrected.map(\.text) == ["with", "passkey", "in", "Laravel"])
        let passkey = corrected[1]
        #expect(passkey.start == 0.3)
        #expect(passkey.end == 0.9)
        #expect(try #require(passkey.confidence) == 0.7)
        // One for one keeps the word's own time.
        #expect(corrected[3].start == 1.2)
        #expect(corrected[3].end == 1.8)
        #expect(corrected[0] == words[0])
    }

    @Test func aSplitWordSharesItsTimeByLength() {
        let one = [TimedWord(text: "ActualBudget", start: 2, end: 3.2)]
        let corrected = VocabularyCorrection.apply("Actual Budget", to: one)
        #expect(corrected.map(\.text) == ["Actual", "Budget"])
        #expect(corrected[0].start == 2)
        #expect(abs(corrected[0].end - 2.6) < 1e-9)
        #expect(corrected[1].start == corrected[0].end)
        #expect(corrected[1].end == 3.2)
    }

    @Test(arguments: [
        ("Final Cut", "Final Cut Pro"),
        ("Final Cut Pro", "Final Cut"),
        ("Cut Pro", "Final Cut Pro"),
        ("Final Cut Pro", "Cut Pro"),
        ("Cut", "Final Cut Pro"),
        ("Final Cut Pro", "Cut"),
        ("Final Pro", "Final Cut Pro"),
        ("Final Cut Pro", "Final Pro"),
        ("Cut", ""),
    ])
    func sharedWordsDontHideCorrections(original: String, replacement: String) {
        let originalWords = original.split(separator: " ").enumerated().map { index, text in
            TimedWord(text: String(text), start: Double(index), end: Double(index + 1))
        }
        let corrections = VocabularyCorrection.corrections(replacement, to: originalWords)
        #expect(!corrections.isEmpty)
        for correction in corrections {
            #expect(!correction.words.isEmpty, "Every correction must attach to original word ids.")
        }
        for (previous, next) in zip(corrections, corrections.dropFirst()) {
            #expect(previous.words.upperBound <= next.words.lowerBound)
        }
        let corrected = VocabularyCorrection.apply(replacement, to: originalWords)
        #expect(corrected.map(\.text).joined(separator: " ") == replacement)
        if !corrected.isEmpty {
            #expect(corrected.first?.start == originalWords.first?.start)
            #expect(corrected.last?.end == originalWords.last?.end)
        }
    }

    @Test func addingASuffixKeepsSurroundingWordsAndAnchorsToAnOriginalWord() {
        let original = [
            TimedWord(text: "use", start: 0, end: 1),
            TimedWord(text: "Final", start: 1, end: 2),
            TimedWord(text: "Cut", start: 2, end: 3),
            TimedWord(text: "today", start: 3, end: 4),
        ]
        #expect(VocabularyCorrection.corrections("use Final Cut Pro today", to: original) == [
            VocabularyCorrection.Correction(words: 2..<3, text: "Cut Pro")
        ])
        let corrected = VocabularyCorrection.apply("use Final Cut Pro today", to: original)
        #expect(corrected.map(\.text) == ["use", "Final", "Cut", "Pro", "today"])
        #expect(Array(corrected.prefix(2)) == Array(original.prefix(2)))
        #expect(corrected.last == original.last)
        #expect(corrected[2].start == 2)
        #expect(corrected[2].end == corrected[3].start)
        #expect(corrected[3].end == 3)
    }

    @Test func noOriginalWordsMeansNoIdsOrTimesToCorrect() {
        #expect(VocabularyCorrection.corrections("Final Cut", to: []).isEmpty)
        #expect(VocabularyCorrection.apply("Final Cut", to: []).isEmpty)
    }
}

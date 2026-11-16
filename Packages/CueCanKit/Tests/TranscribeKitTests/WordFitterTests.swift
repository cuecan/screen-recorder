import Foundation
import ProjectKit
import Testing
@testable import TranscribeKit

struct WordFitterTests {
    /// 10 ms frames over `duration` seconds: speech at −20 dB, quiet at −70 dB inside the silences, and any
    /// frames set by hand.
    func envelope(duration: TimeInterval, silences: [TimeRange], frames: [Int: Double] = [:]) -> SoundEnvelope {
        var levels = (0..<Int(duration * 100)).map { frame -> Double in
            let time = (Double(frame) + 0.5) / 100
            return silences.contains { $0.start <= time && time < $0.end } ? -70 : -20
        }
        for (frame, level) in frames { levels[frame] = level }
        return SoundEnvelope(levels: levels, frameDuration: 0.01)
    }

    func fit(_ words: [TimedWord], silences: [TimeRange], frames: [Int: Double] = [:], duration: TimeInterval = 4) -> [TimedWord] {
        WordFitter.fit(words, silences: silences, envelope: envelope(duration: duration, silences: silences, frames: frames),
                       threshold: -50, duration: duration)
    }

    @Test func aWordTimedInsideASilenceMovesToWhereTheSoundStarts() throws {
        // As in one of real takes: "I" timed 0.4 s into a silence with no sound under it.
        let silence = TimeRange(start: 1.0, end: 2.0)
        let words = [
            TimedWord(text: "Xcode", start: 0.5, end: 1.1),
            TimedWord(text: "I", start: 1.6, end: 1.9),
            TimedWord(text: "bring", start: 1.9, end: 2.3),
            TimedWord(text: "in", start: 2.3, end: 2.6),
            TimedWord(text: "Finder", start: 2.6, end: 3.4),
        ]
        let fitted = fit(words, silences: [silence])
        #expect(fitted.map(\.text) == words.map(\.text))
        #expect(fitted[0].end.isClose(to: 1.0), "A word running into the silence stops at its edge.")
        #expect(fitted[1].start.isClose(to: 2.0), "Nothing starts in the silence.")
        // The words over the next second close up behind it, in order, keeping their proportions.
        #expect(fitted[1].end.isClose(to: 2.0 + 0.3 / 1.4))
        #expect(fitted[2].start.isClose(to: fitted[1].end) && fitted[3].start.isClose(to: fitted[2].end))
        #expect(fitted[4].end.isClose(to: 3.4), "Words past the closing span are unchanged.")
        #expect(fitted.allSatisfy { !(silence.start < $0.start && $0.start < silence.end) })
    }

    @Test func aQuietWordWithSoundUnderItStaysInsideTheSilence() {
        let silence = TimeRange(start: 1.0, end: 2.0)
        let sound = Dictionary(uniqueKeysWithValues: (140..<150).map { ($0, -35.0) })
        let words = [TimedWord(text: "hmm", start: 1.4, end: 1.5), TimedWord(text: "Right", start: 2.0, end: 2.4)]
        let fitted = fit(words, silences: [silence], frames: sound)
        #expect(fitted[0] == words[0])
        #expect(fitted[1] == words[1])
    }

    @Test func anEdgeBetweenWordsMovesToAClearlyQuieterPointNearIt() {
        // A dip at 1.03 s, inside the 80 ms reach of the edge at 1.0 s.
        let dip: [Int: Double] = [102: -35, 103: -35, 104: -35]
        let words = [TimedWord(text: "bring", start: 0.5, end: 1.0), TimedWord(text: "in", start: 1.0, end: 1.5)]
        let fitted = fit(words, silences: [], frames: dip, duration: 2)
        #expect(fitted[0].end.isClose(to: 1.035) && fitted[1].start.isClose(to: 1.035))
    }

    @Test func anEdgeInSteadySoundStaysPut() {
        let words = [TimedWord(text: "bring", start: 0.5, end: 1.0), TimedWord(text: "in", start: 1.0, end: 1.5)]
        let fitted = fit(words, silences: [], duration: 2)
        #expect(fitted == words)
    }

    @Test func soundRunsAreTheStretchesBetweenSilences() {
        let runs = WordFitter.soundRuns(between: [TimeRange(start: 2, end: 3), TimeRange(start: 0, end: 0.5)], duration: 4)
        #expect(runs == [TimeRange(start: 0.5, end: 2), TimeRange(start: 3, end: 4)])
        #expect(WordFitter.soundRuns(between: [TimeRange(start: 0, end: 4)], duration: 4).isEmpty)
    }
}

private extension Double {
    func isClose(to other: Double, tolerance: Double = 1e-6) -> Bool { abs(self - other) <= tolerance }
}

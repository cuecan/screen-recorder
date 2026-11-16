import Foundation
import Testing
@testable import ProjectKit

struct EdgeSoundTests {
    let source = SourceID(number: 1)

    /// 10 ms frames over 4 s: speech at −20 dB in the given stretches, quiet at −70 dB elsewhere, with the
    /// detector's threshold at −50 dB and its 30 ms minimum sound.
    func levels(speech: [(TimeInterval, TimeInterval)], set: [Int: Double] = [:]) -> [SourceID: SourceLevels] {
        var frames = (0..<400).map { frame -> Double in
            let time = (Double(frame) + 0.5) / 100
            return speech.contains { $0.0 <= time && time < $0.1 } ? -20 : -70
        }
        for (frame, level) in set { frames[frame] = level }
        let levels = SourceLevels(source: source, original: .external(URL(filePath: "/tmp/mic.wav")), detector: "energy",
                                  threshold: -50, minimumSound: 0.03, envelope: SoundEnvelope(levels: frames, frameDuration: 0.01))
        return [source: levels]
    }

    func clip(_ number: Int, _ start: TimeInterval, _ end: TimeInterval) -> Clip {
        Clip(id: ClipID(number: number), source: source, sourceIn: start, sourceOut: end)
    }

    @Test func anEdgeInsideAWordIsReportedWithHowFarTheSoundRuns() throws {
        let edit = Edit(main: [clip(1, 0, 1.2), clip(2, 2.5, 4)])
        let found = EdgeSound.edges(in: edit, levels: levels(speech: [(1.0, 1.5)]))
        let edge = try #require(found.first)
        #expect(found.count == 1)
        #expect(edge.clip == ClipID(number: 1) && edge.edge == .end)
        #expect(edge.overSilence.isClose(to: 30))
        #expect(edge.soundBefore.isClose(to: 0.2) && edge.soundAfter.isClose(to: 0.3))
        #expect(edge.toKeepIt.isClose(to: 0.3) && edge.toLeaveItOut.isClose(to: 0.2))
        #expect(edge.timelineTime.isClose(to: 1.2))
    }

    @Test func aStartEdgeInsideAWordKeepsItByMovingEarlier() throws {
        let edit = Edit(main: [clip(1, 1.2, 3)])
        let edge = try #require(EdgeSound.edges(in: edit, levels: levels(speech: [(1.0, 1.5)])).first)
        #expect(edge.edge == .start)
        #expect(edge.toKeepIt.isClose(to: 0.2) && edge.toLeaveItOut.isClose(to: 0.3))
    }

    @Test func edgesWhereSoundStartsOrStopsAreClean() {
        // The clip starts right as the word does and ends right as it stops.
        let edit = Edit(main: [clip(1, 1.0, 1.5)])
        #expect(EdgeSound.edges(in: edit, levels: levels(speech: [(1.0, 1.5)])).isEmpty)
    }

    @Test func edgesInQuietAreClean() {
        let edit = Edit(main: [clip(1, 0.5, 2.5)])
        #expect(EdgeSound.edges(in: edit, levels: levels(speech: [(1.0, 1.5)])).isEmpty)
    }

    @Test func soundTooShortForTheDetectorDoesNotCount() {
        // A 20 ms click across the edge, shorter than the detector's 30 ms.
        let edit = Edit(main: [clip(1, 0, 2.0)])
        #expect(EdgeSound.edges(in: edit, levels: levels(speech: [(1.99, 2.01)])).isEmpty)
        #expect(EdgeSound.edges(in: edit, levels: levels(speech: [(1.98, 2.02)])).count == 1, "40 ms counts.")
    }

    @Test func aJoinThatRollsAndAMutedClipAreLeftOut() {
        let speech = levels(speech: [(1.0, 1.5)])
        let split = Edit(main: [clip(1, 0, 1.2), clip(2, 1.2, 3)])
        #expect(EdgeSound.edges(in: split, levels: speech).isEmpty, "The halves of a split play straight on.")
        var muted = clip(1, 0, 1.2)
        muted.isMuted = true
        #expect(EdgeSound.edges(in: Edit(main: [muted]), levels: speech).isEmpty)
        #expect(EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.2)]), levels: [:]).isEmpty, "No levels, nothing measured.")
    }

    @Test func aFlaggedEdgeInRunningSpeechNamesTheNearestDipsEitherSide() throws {
        // One stretch of speech, 1.0–2.0 s, with gaps between words at 1.30 s and 1.70 s, 20 dB down.
        let speech = levels(speech: [(1.0, 2.0)], set: [130: -40, 170: -40])
        let edge = try #require(EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.5)]), levels: speech).first)
        #expect(try #require(edge.dipBefore).isClose(to: 0.195))
        #expect(try #require(edge.dipAfter).isClose(to: 0.205))
        #expect(edge.soundBefore.isClose(to: 0.5) && edge.soundAfter.isClose(to: 0.5), "The gaps aren't quiet enough to end the sound.")
    }

    @Test func anEdgeAtADipIsBetweenWordsAndClean() {
        let speech = levels(speech: [(1.0, 2.0)], set: [130: -40])
        #expect(EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.30)]), levels: speech).isEmpty)
        #expect(EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.31)]), levels: speech).isEmpty)
        #expect(EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.36)]), levels: speech).count == 1, "A few frames off the dip is in the word.")
    }

    @Test func onlyEdgesAChangeMadeOrMovedAreNew() {
        let speech = levels(speech: [(1.0, 1.5), (2.0, 2.5)])
        let before = EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.2), clip(2, 3, 4)]), levels: speech)
        let after = EdgeSound.edges(in: Edit(main: [clip(1, 0, 1.2), clip(2, 2.2, 4)]), levels: speech)
        let new = EdgeSound.new(in: after, comparedTo: before)
        #expect(new.map(\.clip) == [ClipID(number: 2)] && new.first?.edge == .start)
    }

    @Test func levelsKeepATenthOfADecibelThroughTheirFile() throws {
        let envelope = SoundEnvelope(levels: [-20.04, -71.26, 0, -3000], frameDuration: 0.01, start: 1.5)
        let levels = SourceLevels(source: source, original: .external(URL(filePath: "/tmp/mic.wav")), detector: "energy",
                                  threshold: -48.3, minimumSound: 0.03, envelope: envelope)
        let decoded = try ProjectJSON.decoder.decode(SourceLevels.self, from: ProjectJSON.encoder.encode(levels))
        #expect(decoded == levels)
        #expect(decoded.envelope.levels == [-20, -71.3, 0, -300], "Kept to a tenth, and within ±300 dB.")
        #expect(decoded.envelope.start == 1.5)
    }

    @Test func levelsFromAnotherFileDoNotApply() throws {
        let folder = try ProjectFolder.create(at: try makeTemporaryFolder(), title: "Levels")
        let mic = FileReference.external(URL(filePath: "/tmp/mic.wav"))
        let levels = SourceLevels(source: source, original: mic, detector: "energy", threshold: -50, minimumSound: 0.03,
                                  envelope: SoundEnvelope(levels: [-20], frameDuration: 0.01))
        try folder.saveLevels(levels)
        #expect(folder.loadLevels(for: source, original: mic) == levels)
        #expect(folder.loadLevels(for: source, original: .external(URL(filePath: "/tmp/other.wav"))) == nil)
    }
}

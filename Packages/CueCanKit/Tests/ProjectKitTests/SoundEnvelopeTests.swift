import Foundation
import Testing
@testable import ProjectKit

struct SoundEnvelopeTests {
    /// Speech at −20 dB, 10 ms frames, with whatever dips are set.
    func envelope(_ dips: [Int: Double], count: Int = 200) -> SoundEnvelope {
        var levels = [Double](repeating: -20, count: count)
        for (frame, level) in dips { levels[frame] = level }
        return SoundEnvelope(levels: levels, frameDuration: 0.01)
    }

    @Test func aDeepEnoughDipIsFoundAtItsBottom() throws {
        let sound = envelope([99: -28, 100: -34, 101: -27])
        let dip = try #require(sound.dip(in: TimeRange(start: 0.9, end: 1.1)))
        #expect(dip.isClose(to: 1.005))
    }

    @Test func aShallowDipIsNotADip() {
        let sound = envelope([100: -24])
        #expect(sound.dip(in: TimeRange(start: 0.9, end: 1.1)) == nil, "4 dB under the sound around it is a wobble, not a gap.")
    }

    @Test func aSlopeIntoADipOutsideTheStretchIsNotADip() {
        // Falling towards a dip at 1.2 s; the stretch ends before its bottom.
        let sound = envelope([115: -24, 116: -27, 117: -30, 118: -33, 119: -36, 120: -40, 121: -30])
        #expect(sound.dip(in: TimeRange(start: 1.1, end: 1.18)) == nil)
        #expect(sound.dip(in: TimeRange(start: 1.1, end: 1.25)).map { $0.isClose(to: 1.205) } == true)
    }

    @Test func theFlatQuietOfASilenceHasNoDip() {
        let quiet = SoundEnvelope(levels: [Double](repeating: -70, count: 100), frameDuration: 0.01)
        #expect(quiet.dip(in: TimeRange(start: 0.2, end: 0.8)) == nil)
    }

    @Test func ofTwoEquallyDeepDipsTheNearerWins() throws {
        let sound = envelope([90: -40, 110: -40])
        #expect(try #require(sound.dip(in: TimeRange(start: 0.85, end: 1.15), near: 1.08)).isClose(to: 1.105))
        #expect(try #require(sound.dip(in: TimeRange(start: 0.85, end: 1.15), near: 0.92)).isClose(to: 0.905))
    }

    @Test func theNearestDipIsFoundLookingOneWay() throws {
        let sound = envelope([90: -40, 130: -40])
        let start = 1.1
        #expect(try #require(sound.nearestDip(from: start, forward: true, within: 0.5)).isClose(to: 1.305))
        #expect(try #require(sound.nearestDip(from: start, forward: false, within: 0.5)).isClose(to: 0.905))
        #expect(sound.nearestDip(from: start, forward: true, within: 0.1) == nil, "Not that far.")
        #expect(sound.isDip(90) && !sound.isDip(91))
    }

    @Test func theQuietestFrameIsSmoothedOverItsNeighbours() throws {
        // One odd quiet frame beside loud ones loses to a wider, slightly louder trough.
        let sound = envelope([50: -40, 60: -34, 61: -35, 62: -34])
        #expect(try #require(sound.quietest(in: TimeRange(start: 0.45, end: 0.7))).isClose(to: 0.615))
    }

    @Test func framesAreCountedFromTheEnvelopesStart() {
        let sound = SoundEnvelope(levels: [-20, -40, -20], frameDuration: 0.02, start: 10)
        #expect(sound.frame(at: 10.025) == 1)
        #expect(sound.time(ofFrame: 1).isClose(to: 10.03))
        #expect(sound.end.isClose(to: 10.06))
    }
}

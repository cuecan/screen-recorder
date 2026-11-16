import Testing
@testable import ProjectKit

struct ClipSpeedSelectionTests {
    @Test func frameNudgesUseTheTimelineClockAtEveryPlaybackSpeed() throws {
        for rate in ClipSpeed.rates {
            let speed = try #require(ClipSpeed(rate: rate))
            for frames in [-10, -1, 1, 10] {
                let source = speed.sourceOffset(forTimelineFrames: frames, frameDuration: 1.0 / 56)
                #expect(abs(source / rate - Double(frames) / 56) < 1e-10)
            }
        }
    }

    @Test func mixedRatesDoNotMasqueradeAsTheFirstClip() throws {
        var first = Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 2)
        let second = Clip(id: ClipID(number: 2), source: SourceID(number: 1), sourceIn: 2, sourceOut: 4)
        first.speed = try #require(ClipSpeed(rate: 1.5))
        let values = ClipSpeedSelection(clips: [first, second])
        #expect(values.rate == nil)
        #expect(values.sound == .pitchKept)
    }

    @Test func uniformAndMixedSoundAreIndependentOfTheRate() throws {
        var first = Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 2)
        var second = Clip(id: ClipID(number: 2), source: SourceID(number: 1), sourceIn: 2, sourceOut: 4)
        first.speed = try #require(ClipSpeed(rate: 2, sound: .muted))
        second.speed = try #require(ClipSpeed(rate: 2))
        #expect(ClipSpeedSelection(clips: [first, second]).rate == 2)
        #expect(ClipSpeedSelection(clips: [first, second]).sound == nil)
        #expect(ClipSpeedSelection(clips: [first]).sound == .muted)
        #expect(ClipSpeedSelection(clips: []).rate == nil)
    }
}

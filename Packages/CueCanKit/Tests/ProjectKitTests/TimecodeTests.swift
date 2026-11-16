import Testing
@testable import ProjectKit

@Suite struct TimecodeTests {
    @Test func minutesSecondsAndFrames() {
        let timecode = Timecode(frameRate: 30)
        #expect(timecode.string(0) == "0:00:00")
        #expect(timecode.string(62.5) == "1:02:15")
        #expect(timecode.string(3.2) == "0:03:06")
    }

    @Test func everyFrameStepMovesTheFrameByOne() {
        let timecode = Timecode(frameRate: 30)
        let duration = 1.0 / 30
        #expect(timecode.string(7 * duration) == "0:00:07")
        #expect(timecode.string(29 * duration) == "0:00:29")
        #expect(timecode.string(30 * duration) == "0:01:00")
    }

    @Test func hoursAppearFromAnHourOn() {
        #expect(Timecode(frameRate: 25).string(3723.04) == "1:02:03:01")
    }

    @Test func frameRateFromAFrameDuration() {
        #expect(Timecode(frameDuration: 1.0 / 60).frameRate == 60)
        #expect(Timecode(frameDuration: 0).frameRate == 30)
    }

    @Test func negativeTimesShowZero() {
        #expect(Timecode(frameRate: 30).string(-1) == "0:00:00")
    }
}

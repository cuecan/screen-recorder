import Testing
@testable import RecorderKit

struct SyncCalibrationProgressTests {
    let measurement = SyncMeasurement(flashes: [1, 3, 5, 7, 9], beeps: [0.9, 2.9, 4.9, 6.9, 8.9])

    @Test func cancelledAndSupersededRunsCannotPublishProgressOrFailure() {
        var progress = SyncCalibrationProgress()
        let old = progress.begin()
        progress.reset()
        progress.fail("Old permission reply", for: old)
        #expect(progress.state == .ready)
        let next = progress.begin()
        progress.listening(measurement, for: old)
        progress.complete(measurement, for: old)
        progress.fail("Old failure", for: old)
        #expect(progress.state == .starting(next))
        progress.listening(measurement, for: next)
        #expect(progress.state == .listening(next, measurement))
        progress.complete(measurement, for: next)
        #expect(!progress.isRunning)
        progress.fail("Late failure", for: next)
        #expect(progress.state == .measured(measurement))
    }
}

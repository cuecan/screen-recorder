import Testing
@testable import AudioKit

struct MasteringCancellationTests {
    @Test(arguments: [1, 10, 50, 100])
    func cancellationInterruptsMasteringBeforeItFinishes(at checkpoint: Int) {
        let audio = TruePeakLimiterTests().spiky()
        var visits = 0
        #expect(throws: CancellationError.self) {
            try LoudnessStage.process(audio, checkpoint: {
                visits += 1
                if visits == checkpoint { throw CancellationError() }
            })
        }
        #expect(visits == checkpoint)
    }

    @Test func anUncancelledMasteringRunKeepsItsExactSamplesAndMeasurements() throws {
        let audio = TruePeakLimiterTests().spiky()
        let ordinary = LoudnessStage.process(audio)
        let cancellable = try LoudnessStage.process(audio, checkpoint: { try Task.checkCancellation() })
        #expect(ordinary.audio == cancellable.audio)
        #expect(ordinary.loudness == cancellable.loudness)
        #expect(ordinary.truePeak == cancellable.truePeak)
        #expect(ordinary.limiterReduction == cancellable.limiterReduction)
    }
}

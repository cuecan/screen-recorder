import Foundation
import Testing
@testable import ProjectKit

struct TrimPreviewPlanTests {
    private func clip(_ id: Int, _ start: Double, _ end: Double) -> Clip {
        Clip(id: ClipID(number: id), source: SourceID(number: 1), sourceIn: start, sourceOut: end)
    }

    @Test func invalidTransientTimesCannotCrashTheFrameDelta() {
        let edit = Edit(main: [clip(1, 0, 5)])
        for time in [Double.nan, Double.infinity, Double.greatestFiniteMagnitude] {
            #expect(throws: EditError.self) {
                try TrimPreviewPlan(edit: edit, clip: ClipID(number: 1), edge: .end, sourceTime: time,
                                    sourceDuration: nil, frameDuration: 1.0 / 60)
            }
        }
        for duration in [0.0, Double.leastNonzeroMagnitude, Double.nan, Double.infinity] {
            #expect(throws: EditError.self) {
                try TrimPreviewPlan(edit: edit, clip: ClipID(number: 1), edge: .end, sourceTime: 4,
                                    sourceDuration: 5, frameDuration: duration)
            }
        }
    }

    @Test func aRollShowsTheFramesMeetingAtTheMovedJoinWithoutChangingTheOriginal() throws {
        let original = Edit(main: [clip(1, 0, 5), clip(2, 5, 10)])
        let plan = try TrimPreviewPlan(edit: original, clip: ClipID(number: 1), edge: .end, sourceTime: 6,
                                       sourceDuration: 10, frameDuration: 1.0 / 60)
        #expect(original.main[0].playedRange.end == 5)
        #expect(plan.edit.duration == original.duration)
        #expect(plan.cut == 6)
        #expect(plan.outgoing?.clip == ClipID(number: 1))
        #expect(abs((plan.outgoing?.time ?? 0) - 359.0 / 60) < 1e-9)
        #expect(plan.incoming?.clip == ClipID(number: 2))
        #expect(plan.incoming?.time == 6)
        #expect(plan.deltaFrames == 60)
    }

    @Test func aRippleAndAStartTrimUseTheCandidateTimelineAndRespectEmptySides() throws {
        let original = Edit(main: [clip(1, 0, 5), clip(2, 7, 10)])
        let end = try TrimPreviewPlan(edit: original, clip: ClipID(number: 1), edge: .end, sourceTime: 4,
                                      sourceDuration: 10, frameDuration: 1.0 / 30)
        #expect(end.cut == 4 && end.incoming?.time == 4)
        #expect(end.edit.duration == 7)
        let start = try TrimPreviewPlan(edit: original, clip: ClipID(number: 1), edge: .start, sourceTime: 0,
                                        sourceDuration: 10, frameDuration: 1.0 / 30)
        #expect(start.outgoing == nil && start.incoming?.time == 0)
        #expect(start.atLimit)
        let last = try TrimPreviewPlan(edit: original, clip: ClipID(number: 2), edge: .end, sourceTime: 10,
                                       sourceDuration: 10, frameDuration: 1.0 / 30)
        #expect(last.incoming == nil && last.atLimit)
    }

    @Test func fractionalCutsAndSpeedUseOutputFramesRatherThanSourceFrames() throws {
        var edit = Edit(main: [clip(1, 0, 5), clip(2, 7, 10)])
        edit.main[0].speed = try #require(ClipSpeed(rate: 2))
        let plan = try TrimPreviewPlan(edit: edit, clip: ClipID(number: 1), edge: .end, sourceTime: 4.01,
                                       sourceDuration: 10, frameDuration: 1.0 / 60)
        #expect(abs(plan.cut - 2.005) < 1e-9)
        #expect(plan.outgoing?.time == 2)
        #expect(abs((plan.incoming?.time ?? 0) - 121.0 / 60) < 1e-9)
        #expect(plan.deltaFrames == -30)
    }
}

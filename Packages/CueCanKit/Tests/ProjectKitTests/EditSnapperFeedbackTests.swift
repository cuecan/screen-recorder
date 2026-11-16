import Foundation
import Testing
@testable import ProjectKit

struct EditSnapperFeedbackTests {
    @Test func feedbackDistinguishesSilenceAndScreenPointsThroughRetiming() throws {
        let source = SourceID(number: 1)
        let edit = Edit(main: [Clip(id: ClipID(number: 1), source: source, sourceIn: 0, sourceOut: 7,
                                    speed: try #require(ClipSpeed(rate: 2)))])
        let snapper = EditSnapper(transcripts: TranscriptIndex([talkingHead]), stillMoments: [source: [3.234]])
        // "there." into the pause, padded as a cut by id is, at 2×.
        let edge = CutPointSnapper(transcript: talkingHead).boundary(before: 3) / 2
        let silence = snapper.snap(edge + 0.001, in: edit, tolerance: 0.005)
        #expect(silence.target == .silenceEdge)
        #expect(abs(silence.time - edge) < 1e-9)
        let screen = snapper.snap(1.618, in: edit, tolerance: 0.005)
        #expect(screen.target == .screenStill)
        #expect(abs(screen.time - 1.617) < 1e-9)
    }

    @Test func screenPointsWithoutASpeechTranscriptKeepTheirExactTimeAndIdentity() {
        let source = SourceID(number: 1)
        let edit = Edit(main: [Clip(id: ClipID(number: 1), source: source, sourceIn: 0, sourceOut: 5)])
        let snapper = EditSnapper(transcripts: TranscriptIndex([]), stillMoments: [source: [2.123456, 2.123456]])
        let snapped = snapper.snap(2.124, in: edit, tolerance: 0.001)
        #expect(snapped.target == .screenStill)
        #expect(snapped.time == 2.123456)
    }
}

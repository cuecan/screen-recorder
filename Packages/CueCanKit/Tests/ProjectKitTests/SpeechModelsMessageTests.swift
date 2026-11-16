import Foundation
import Testing
@testable import ProjectKit

/// What the helper says about the speech models, as the setup window reads it (docs/decisions.md, 93).
struct SpeechModelsMessageTests {
    @Test(arguments: [SpeechModelsMessage.progress(0.42), .ready, .missing, .failed("No internet")])
    func everyMessageSurvivesItsLine(message: SpeechModelsMessage) throws {
        #expect(try SpeechModelsMessage.read(try message.line()) == message)
    }

    @Test func theAnswerIsTheLastLine() throws {
        let lines = try [SpeechModelsMessage.progress(0), .progress(0.5), .ready].map { try $0.line() }.joined(separator: "\n")
        #expect(SpeechModelsMessage.result(in: .init(status: 0, standardOutput: lines + "\n", standardError: "")) == .ready)
        #expect(SpeechModelsMessage.result(in: .init(status: 0, standardOutput: try SpeechModelsMessage.missing.line(), standardError: "")) == .missing)
    }

    @Test func aHelperThatStoppedPartWayIsAFailureNeverReady() throws {
        let partWay = try SpeechModelsMessage.progress(0.9).line()
        for output in ["", "not json", partWay] {
            guard case .failed = SpeechModelsMessage.result(in: .init(status: 1, standardOutput: output, standardError: "")) else {
                Issue.record("\(output.debugDescription) must read as a failure.")
                continue
            }
        }
    }

    @Test func theBarGivesEachModelItsShareOfTheDownload() {
        #expect(SpeechModelsProgress.overall(transcription: 0) == 0)
        #expect(abs(SpeechModelsProgress.overall(transcription: 0.5) - 235 / 955.5) < 1e-9)
        #expect(SpeechModelsProgress.overall(transcription: 1) == SpeechModelsProgress.transcriptionShare)
        #expect(SpeechModelsProgress.overall(transcription: 7) == SpeechModelsProgress.transcriptionShare)
        // The timing model comes last, after the vocabulary model, and ends the bar.
        #expect(abs(SpeechModelsProgress.overall(timing: 0) - 567.5 / 955.5) < 1e-9)
        #expect(SpeechModelsProgress.overall(timing: 0) > SpeechModelsProgress.transcriptionShare)
        #expect(abs(SpeechModelsProgress.overall(timing: 1) - 1) < 1e-9)
    }
}

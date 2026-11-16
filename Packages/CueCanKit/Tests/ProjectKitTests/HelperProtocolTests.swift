import Foundation
import Testing
import ProjectKit

struct HelperProtocolTests {
    @Test func pathsAndWarningsAreDataRegardlessOfTheirWording() throws {
        let result = ExportResult(files: [URL(filePath: "/tmp/A file\nwith a newline.fcpxml")], warnings: ["Couldn't clean the mic; raw audio was used."])
        let line = try HelperMessage.exported(result).line()
        #expect(!line.contains("\n"))
        let response = try HelperMessage.result(in: .init(status: 0, standardOutput: line + "\n", standardError: "Framework diagnostic"))
        #expect(response == .exported(result))
        var job = ExportJob()
        let attempt = try #require({ job.start([.handoff]) }())
        job.complete(.handoff, files: result.files, attempt: attempt)
        job.finish(.success, attempt: attempt, warnings: result.warnings)
        #expect(job.warnings == result.warnings)
        job.reset()
        #expect(job.warnings.isEmpty)
    }

    @Test func partialProcessingFailuresAndTopLevelErrorsSurviveTheProtocol() throws {
        var report = ProcessingReport()
        report.failures[SourceID(number: 1)] = "Missing audio"
        report.failures[SourceID(number: 2)] = "Disk full"
        let progress = ProcessingProgress(stage: .cleaning, source: SourceID(number: 1), message: "Different wording")
        let lines = try [HelperMessage.progress(progress), .processed(report)].map { try $0.line() }.joined(separator: "\n")
        #expect(try HelperMessage.result(in: .init(status: 1, standardOutput: lines, standardError: "")) == .processed(report))
        #expect(report.problem?.contains("Missing audio") == true)
        #expect(report.problem?.contains("Disk full") == true)
        let error = try HelperMessage.failed("The project cannot be read.").line()
        do {
            _ = try HelperMessage.result(in: .init(status: 1, standardOutput: error, standardError: ""))
            Issue.record("Expected the helper's error")
        } catch let failure as HelperMessage.Failure {
            #expect(failure.message == "The project cannot be read.")
        }
    }

    @Test func extraResultsAndNonzeroExportExitCannotLookSuccessful() throws {
        let line = try HelperMessage.exported(.init(files: [])).line()
        #expect(throws: HelperMessage.Failure.self) {
            try HelperMessage.result(in: .init(status: 0, standardOutput: line + "\n" + line, standardError: ""))
        }
        #expect(throws: HelperMessage.Failure.self) {
            try HelperMessage.result(in: .init(status: 1, standardOutput: line, standardError: ""))
        }
    }

    @Test func missingOrMalformedResultsCannotLookSuccessful() {
        for output in ["", "Wrote:\n/tmp/file", "{broken"] {
            #expect(throws: (any Error).self) {
                try HelperMessage.result(in: .init(status: 0, standardOutput: output, standardError: ""))
            }
        }
    }
}

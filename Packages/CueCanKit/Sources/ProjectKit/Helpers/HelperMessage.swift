import Foundation

/// JSON Lines spoken by the bundled helper in `--machine` mode. Human output is never parsed as data.
public enum HelperMessage: Codable, Sendable, Equatable {
    case progress(ProcessingProgress)
    case processed(ProcessingReport)
    case exported(ExportResult)
    /// A fix's words timed against the audio; empty when it couldn't be (docs/decisions.md, 69).
    case aligned([AlignedWord])
    case failed(String)

    public func line() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
    public static func read(_ line: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(line.utf8))
    }
    /// Requires a terminal response. Unexpected output is an error rather than a fabricated success.
    public static func result(in output: CommandRunner.Output) throws -> Self {
        let messages = try output.standardOutput.split(separator: "\n").map { try read(String($0)) }
        guard let last = messages.last else { throw Failure("The helper stopped without reporting a result.") }
        guard messages.dropLast().allSatisfy({ if case .progress = $0 { true } else { false } }) else {
            throw Failure("The helper reported more than one result.")
        }
        if case .failed(let message) = last { throw Failure(message) }
        switch last {
        case .processed(let report):
            guard output.status == 0 || report.problem != nil else { throw Failure("Processing stopped before it finished.") }
        case .exported:
            guard output.status == 0 else { throw Failure("The export stopped before it finished.") }
        case .aligned:
            guard output.status == 0 else { throw Failure("Timing the fix stopped before it finished.") }
        default: throw Failure("The helper stopped without reporting a result.")
        }
        return last
    }
    public struct Failure: Error, LocalizedError, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }
}

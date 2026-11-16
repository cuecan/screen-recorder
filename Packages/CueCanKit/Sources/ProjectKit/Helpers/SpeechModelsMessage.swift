import Foundation

/// What `cuecan --machine models` reports, a line of JSON at a time: the app can't load the speech models'
/// code itself (docs/architecture.md), so it asks the helper whether they're here and has it fetch them.
public enum SpeechModelsMessage: Codable, Sendable, Equatable {
    /// The fraction downloaded so far, from 0 to 1.
    case progress(Double)
    /// The models are on this Mac.
    case ready
    /// They aren't, or not whole.
    case missing
    case failed(String)

    public func line() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }

    public static func read(_ line: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(line.utf8))
    }

    /// The helper's answer: its last line. A helper that stopped without one is a failure, never "ready".
    public static func result(in output: CommandRunner.Output) -> Self {
        guard let last = output.standardOutput.split(separator: "\n").last, let message = try? read(String(last)) else {
            return .failed("The download stopped before it finished.")
        }
        if case .progress = message { return .failed("The download stopped before it finished.") }
        return message
    }
}

/// How the three models share one progress bar, by size: the transcription model (470 MB) and the vocabulary
/// model (97.5 MB), as docs/ui.md, board 12, has them, and the timing model's weights (388 MB; decision 95).
public enum SpeechModelsProgress {
    static let transcriptionSize = 470.0, timingSize = 388.0, vocabularySize = 97.5
    static let total = transcriptionSize + timingSize + vocabularySize

    /// The transcription model's part of the download. It comes first.
    public static let transcriptionShare = transcriptionSize / total
    /// Where the bar stands once the vocabulary model, which comes second and reports no progress, is done.
    public static let beforeTiming = (transcriptionSize + vocabularySize) / total
    /// The timing model's part. It comes last, so a problem fetching it leaves the other two in place.
    public static let timingShare = timingSize / total

    /// The whole download's fraction while the transcription model is at `fraction`.
    public static func overall(transcription fraction: Double) -> Double {
        min(max(fraction, 0), 1) * transcriptionShare
    }

    /// The whole download's fraction while the timing model is at `fraction`.
    public static func overall(timing fraction: Double) -> Double {
        beforeTiming + min(max(fraction, 0), 1) * timingShare
    }
}

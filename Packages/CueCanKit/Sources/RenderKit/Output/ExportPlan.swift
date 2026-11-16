import Foundation
import ProjectKit

/// One export's frozen inputs and choices, also transferable to the isolated helper process.
public struct ExportPlan: Codable, Sendable {
    public enum Kind: Codable, Sendable {
        case finished(outputs: [OutputShape], transcript: Bool, settings: ExportSettings)
        case handoff(splitAtSilences: Bool)
    }
    public let inputs: RenderInputs
    public let destination: URL
    public let kind: Kind
    public let baseName: String
    public var items: [ExportJob.Item] {
        switch kind {
        case .finished(let outputs, let transcript, _): outputs.map { .video($0) } + (transcript ? [.transcript] : [])
        case .handoff: [.handoff]
        }
    }
    public init(inputs: RenderInputs, destination: URL, kind: Kind, name: String? = nil) {
        self.inputs = inputs
        self.destination = destination
        self.kind = kind
        self.baseName = Self.baseName(name ?? inputs.project.title)
    }

    /// The files the creator reviews before exporting, shared by naming and collision checks.
    public var outputURLs: [URL] {
        switch kind {
        case .finished(let outputs, let transcript, _):
            outputs.map(videoURL) + (transcript ? [fileURL(extension: "srt"), fileURL(extension: "txt")] : [])
        case .handoff:
            [fileURL(extension: "fcpxml"), fileURL(extension: "srt"), fileURL(extension: "txt")]
        }
    }

    /// The app asks for another name rather than silently replacing an earlier export.
    public func existingOutputs(fileManager: FileManager = .default) -> [URL] {
        outputURLs.filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }
    public func videoURL(_ output: OutputShape) -> URL {
        destination.appending(path: "\(baseName)\(output == .landscape ? "" : " Short").mp4")
    }
    public func fileURL(extension suffix: String) -> URL { destination.appending(path: "\(baseName).\(suffix)") }
    public static func baseName(_ title: String) -> String {
        let cleaned = String(title.map { "/:\\".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Export" : cleaned
    }
    public func write(to url: URL) throws { try JSONEncoder().encode(self).write(to: url, options: .atomic) }
    public static func read(from url: URL) throws -> Self { try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
}

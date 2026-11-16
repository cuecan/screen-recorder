import Foundation

/// Files actually written by an export, and warnings that must remain visible to its caller.
public struct ExportResult: Codable, Sendable, Equatable {
    public let files: [URL]
    public let warnings: [String]
    public init(files: [URL], warnings: [String] = []) {
        self.files = files
        self.warnings = warnings
    }
}

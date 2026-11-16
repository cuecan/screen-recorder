import Foundation
import ProjectKit

/// What a tool hands back: text for Claude to read, and any stills for it to look at.
struct ToolOutput: Sendable {
    struct Image: Sendable {
        var data: Data
        var mimeType: String
    }

    var text: String
    var images: [Image] = []
    var exported: ExportResult?

    /// A value as readable JSON.
    static func json(_ value: some Encodable) throws -> ToolOutput {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return ToolOutput(text: String(decoding: data, as: UTF8.self))
    }
}

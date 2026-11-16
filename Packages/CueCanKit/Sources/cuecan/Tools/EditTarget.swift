import ProjectKit

/// Exactly one coordinate system for an edit request, decoded before any mutation.
enum EditTarget: Equatable {
    case words(ItemRange)
    case timeline(TimeRange)
    case source(SourceID, TimeRange)

    static func read(_ arguments: ToolArguments, firstWord: String = "start_id", lastWord: String = "end_id",
                     sourceKey: String? = "source_id") throws -> Self {
        let words = arguments.has(firstWord) || arguments.has(lastWord)
        let times = arguments.has("start_time") || arguments.has("end_time")
        let source = try sourceKey.flatMap { try arguments.optionalSourceID($0) }
        if words {
            guard !times, source == nil else { throw ToolError.invalidValue(firstWord, "give words or time in one coordinate system, not both.") }
            return .words(try arguments.range(from: firstWord, to: lastWord))
        }
        let range = try arguments.timeRange()
        return source.map { .source($0, range) } ?? .timeline(range)
    }
}

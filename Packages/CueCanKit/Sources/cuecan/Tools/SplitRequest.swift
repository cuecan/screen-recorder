import Foundation
import ProjectKit

/// A split uses a timeline time or a particular word in a particular clip.
enum SplitRequest {
    case time(TimeInterval)
    case word(ClipID, WordID)
    init(_ arguments: ToolArguments) throws {
        if let time = try arguments.optionalDouble("time") {
            try arguments.reject(["clip_id", "before_word_id"], because: "give a timeline time or a clip and word, not both.")
            self = .time(time)
        } else { self = .word(try arguments.clipID("clip_id"), try arguments.wordID("before_word_id")) }
    }
}

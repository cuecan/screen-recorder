import Foundation
import ProjectKit

/// Separate creation, removal by identity, and removal by timeline range.
enum FreezeRequest {
    case create(TimeRange, frame: TimeInterval?)
    case remove(FreezeID)
    case removeRange(TimeRange)
    init(_ arguments: ToolArguments) throws {
        if try arguments.optionalBool("remove") == true {
            try arguments.reject(["frame_time"], because: "a removal cannot choose a frame.")
            if let id = try arguments.optionalFreezeID("freeze_id") {
                try arguments.reject(["start_time", "end_time"], because: "remove by freeze id or time range, not both.")
                self = .remove(id)
            } else { self = .removeRange(try arguments.timeRange()) }
        } else {
            try arguments.reject(["freeze_id"], because: "a freeze id is used only for removal.")
            self = .create(try arguments.timeRange(), frame: try arguments.optionalDouble("frame_time"))
        }
    }
}

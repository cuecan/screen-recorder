import Foundation

/// One frame of the edit as a JPEG, for Claude to look at before rendering.
public struct Still: Sendable, Equatable {
    /// Where on the edited timeline it was taken, in seconds.
    public var time: TimeInterval
    public var jpeg: Data
    public var width: Int
    public var height: Int
}

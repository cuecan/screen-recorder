import Foundation

/// When a beta build stops starting new recordings (docs/decisions.md, 98).
///
/// A release build carries the day it was made; it records for `days` after that. What's already recorded
/// still opens, edits and exports afterwards, and every update carries a later day. A build with no day,
/// such as one run from Xcode, never ends.
public struct BetaExpiry: Equatable, Sendable {
    /// How long a build records for.
    public static let days = 90

    /// The first moment the build no longer records: midnight UTC, `days` after the day it was made.
    public let ends: Date

    /// - Parameter builtOn: the day the build was made, as `2026-11-15`, in UTC. Nil, empty or anything
    ///   else means the build has no end.
    public init?(builtOn: String?) {
        guard let builtOn = builtOn?.trimmingCharacters(in: .whitespaces), !builtOn.isEmpty,
              let made = try? Date(builtOn, strategy: .iso8601.year().month().day())
        else { return nil }
        ends = made.addingTimeInterval(TimeInterval(Self.days) * 24 * 60 * 60)
    }

    /// Whether the build has stopped recording.
    public func hasEnded(at now: Date) -> Bool { now >= ends }
}

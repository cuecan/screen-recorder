import Foundation

/// How far a cut sits from the speech on either side of a real silence.
///
/// The defaults are starting values to tune by ear in the bake-off (TEST NEEDED: no clipped first
/// sounds, no awkward tails). They aren't measured.
public struct SnapSettings: Codable, Equatable, Sendable {
    /// How much silence to keep before a word starts, so its first sound isn't clipped.
    public var leadPad: TimeInterval
    /// How much silence to keep after a word ends, so its tail can fade out.
    public var trailPad: TimeInterval

    public init(leadPad: TimeInterval = 0.08, trailPad: TimeInterval = 0.15) {
        self.leadPad = leadPad
        self.trailPad = trailPad
    }

    public static let `default` = SnapSettings()
}

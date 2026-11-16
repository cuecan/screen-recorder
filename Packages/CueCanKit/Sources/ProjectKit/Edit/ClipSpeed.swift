import Foundation

/// How fast a clip plays, for a wait worth showing rather than cutting (docs/decisions.md, 59).
///
/// Word ids, snapping and the SRT go through the speed, so words land where they're heard.
public struct ClipSpeed: Codable, Hashable, Sendable {
    /// What a sped-up clip's sound does.
    public enum Sound: String, Codable, Sendable, CaseIterable {
        /// The sound plays faster at the same pitch.
        case pitchKept
        /// The clip plays silently.
        case muted
    }

    /// The speeds offered. Claude's proposal, AUTHOR'S TAKE NEEDED.
    public static let rates: [Double] = [1, 1.5, 2, 4, 8]
    /// Above this, a clip is muted unless asked otherwise. Claude's proposal, AUTHOR'S TAKE NEEDED.
    public static let mutedAbove: Double = 2

    public let rate: Double
    public let sound: Sound

    public static let normal = ClipSpeed(uncheckedRate: 1, sound: .pitchKept)

    /// A speed, or nil when the rate isn't one of ``rates``. Without a sound, a rate above
    /// ``mutedAbove`` is muted and the rest keep their pitch.
    public init?(rate: Double, sound: Sound? = nil) {
        guard Self.rates.contains(rate) else { return nil }
        self.init(uncheckedRate: rate, sound: sound ?? (rate > Self.mutedAbove ? .muted : .pitchKept))
    }

    private init(uncheckedRate rate: Double, sound: Sound) {
        self.rate = rate
        self.sound = rate == 1 ? .pitchKept : sound
    }

    public var isNormal: Bool { rate == 1 }

    /// Source seconds corresponding to a number of frames on the edited timeline. A faster clip must
    /// move farther through its recording for the same one-frame change in the editor.
    public func sourceOffset(forTimelineFrames frames: Int, frameDuration: TimeInterval) -> TimeInterval {
        Double(frames) * frameDuration * rate
    }

    /// "4×", "1.5×".
    public var label: String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private enum CodingKeys: String, CodingKey { case rate, sound }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rate = try container.decode(Double.self, forKey: .rate)
        guard let speed = ClipSpeed(rate: rate, sound: try container.decodeIfPresent(Sound.self, forKey: .sound)) else {
            throw DecodingError.dataCorruptedError(forKey: .rate, in: container, debugDescription: "A clip plays at 1, 1.5, 2, 4 or 8 times speed, not \(rate).")
        }
        self = speed
    }
}

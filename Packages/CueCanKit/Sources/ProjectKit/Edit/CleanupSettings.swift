import Foundation

/// The Cleanup stage: removing noise and room echo with Apple's `AUSoundIsolation`, which never regenerates the
/// voice (docs/decisions.md, 5, 33 and 34).
public struct CleanupSettings: Codable, Equatable, Sendable {
    /// Which kind of cleanup. The original is never modified, whichever is chosen.
    public enum Mode: String, Codable, Sendable, CaseIterable {
        /// No cleanup: the raw recording.
        case off
        /// Noise removed without regenerating the voice. The default.
        case natural
    }

    public var mode: Mode
    /// How much of the room is removed, from 0 to 100 percent. Lower keeps more room tone, so the voice
    /// sounds less processed.
    public var amount: Double

    /// 75% is the default, judged by ear on `AUSoundIsolation` (docs/decisions.md, 22).
    public init(mode: Mode = .natural, amount: Double = 75) {
        self.mode = mode
        self.amount = AudioAmount.clamped(amount)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, amount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(Mode.self, forKey: .mode)
        amount = try AudioAmount.decode(from: container, forKey: .amount)
    }
}

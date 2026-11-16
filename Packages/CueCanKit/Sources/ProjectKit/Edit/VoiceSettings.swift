import Foundation

/// The Voice stage: evening out and clarifying the voice with plain DSP, from a preset
/// (docs/decisions.md, 33 and 34).
public struct VoiceSettings: Codable, Equatable, Sendable {
    /// Which preset.
    public enum Preset: String, Codable, Sendable, CaseIterable {
        /// No voice processing.
        case off
        /// Gentle: a high-pass, a little presence and light compression. The default.
        case clear
        /// Stronger compression, more presence and de-essing.
        case broadcast
    }

    public var preset: Preset
    /// How strongly the preset applies, from 0 (nothing) to 100 percent (the full preset). It scales the
    /// preset's settings rather than blending processed and dry audio.
    public var amount: Double

    /// The starting amount isn't decided: 50% until the presets have been judged by ear (AUTHOR'S TAKE NEEDED).
    public init(preset: Preset = .clear, amount: Double = 50) {
        self.preset = preset
        self.amount = AudioAmount.clamped(amount)
    }

    private enum CodingKeys: String, CodingKey {
        case preset, amount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decode(Preset.self, forKey: .preset)
        amount = try AudioAmount.decode(from: container, forKey: .amount)
    }
}

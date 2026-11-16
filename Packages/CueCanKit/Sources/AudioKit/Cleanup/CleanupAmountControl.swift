import Foundation

/// How Cleanup's Amount dial is applied for a model (docs/decisions.md, 34).
public enum CleanupAmountControl: String, Sendable, Codable {
    /// The model's own setting, such as `AUSoundIsolation`'s wet/dry mix.
    case native
    /// A blend of the fully cleaned voice with the original, lined up to the sample first
    /// (``SignalAlignment``).
    case blend
}

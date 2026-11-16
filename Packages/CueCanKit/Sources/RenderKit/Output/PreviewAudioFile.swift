import Foundation

/// Keeps a normalized preview's temporary WAV alive for its player item and cache. Releasing the last
/// owner removes it; a cancelled or replaced preview cannot delete the current player's sound.
public final class PreviewAudioFile: Sendable {
    public let url: URL
    init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}

import Foundation

/// A shape the edit is rendered in: the 16:9 video or the 9:16 Short.
///
/// Built-in exports follow the project's format strictly (docs/decisions.md, 38), so a project renders
/// only the shapes its ``VideoFormat`` includes.
public enum OutputShape: String, Codable, Sendable, CaseIterable, CustomStringConvertible {
    /// The 16:9 video, 1920 × 1080.
    case landscape
    /// The 9:16 Short, 1080 × 1920.
    case vertical

    /// The frame size in pixels at 1080p. A 4K export doubles both.
    public var width: Int { self == .landscape ? 1920 : 1080 }
    public var height: Int { self == .landscape ? 1080 : 1920 }

    /// "16:9" or "9:16".
    public var ratioName: String { self == .landscape ? "16:9" : "9:16" }

    /// The output's name, used for its preview and framing guide.
    public var title: String { self == .landscape ? "Video" : "Short" }
    public var previewLabel: String { "\(title) · \(ratioName)" }

    public var description: String { self == .landscape ? "Video, 16:9" : "Short, 9:16" }
}

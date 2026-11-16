import CoreGraphics
import Foundation

/// A window another app has on screen, which can be snapped into the capture area.
public struct SnappableWindow: Sendable, Hashable, Identifiable {
    public var id: CGWindowID
    public var processID: pid_t
    public var appName: String
    public var title: String
    /// In AppKit's global coordinates, from the bottom left of the main display.
    public var frame: CGRect

    /// "Safari — CueCan docs", or just the app's name.
    public var label: String { title.isEmpty ? appName : "\(appName) — \(title)" }
}

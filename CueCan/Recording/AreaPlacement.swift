import CoreGraphics
import ProjectKit
import RecorderKit

/// Where the capture area is: its size, its frame in AppKit's global coordinates, and its display.
struct AreaPlacement: Equatable {
    var area: CaptureArea
    var frame: CGRect
    var displayID: CGDirectDisplayID
    var displayFrame: CGRect
    /// The display's available desktop, under the menu bar and clear of the Dock. The area starts inside it
    /// and stops at its sides, and can be pulled past them as far as the display's.
    var visibleFrame: CGRect

    /// Whether the area has been pulled over the menu bar or the Dock.
    var reachesPastDesktop: Bool { AreaGeometry.reaches(frame, past: visibleFrame) }
    /// What the area is sized against: the desktop, or the whole display once it reaches past the desktop.
    var bounds: CGRect { reachesPastDesktop ? displayFrame : visibleFrame }
    /// The part of the area a snapped window fills: windows can't go under the menu bar.
    var windowFrame: CGRect { AreaGeometry.windowFrame(in: frame, desktop: visibleFrame) }
}

import CoreGraphics
import ProjectKit

/// Where the capture area is: its size, its frame in AppKit's global coordinates, and its display.
struct AreaPlacement: Equatable {
    var area: CaptureArea
    var frame: CGRect
    var displayID: CGDirectDisplayID
    var displayFrame: CGRect
    /// The display's available desktop, which the area stays inside.
    var visibleFrame: CGRect
}

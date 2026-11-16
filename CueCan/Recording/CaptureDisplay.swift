import AppKit

/// The display choices are refreshed from AppKit, with point sizes to distinguish matching monitors.
struct CaptureDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
}


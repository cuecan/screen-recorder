import AppKit

/// The privacy destinations used by recording setup. Keep Settings' URL identifiers out of views.
enum PrivacyPane: String {
    case camera = "Privacy_Camera"
    case microphone = "Privacy_Microphone"
    case accessibility = "Privacy_Accessibility"
    case screenRecording = "Privacy_ScreenCapture"

    func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}

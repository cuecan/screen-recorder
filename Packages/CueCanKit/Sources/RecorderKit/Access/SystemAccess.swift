import ApplicationServices
import AVFoundation
import Foundation

/// What macOS says about each kind of access, and asking it for one.
public enum SystemAccess {
    /// What macOS reports now, without asking.
    ///
    /// Screen Recording and Accessibility report only allowed or not: macOS doesn't say whether it was ever
    /// asked for. Screen Recording can also go on reporting "not allowed" after its switch is turned on, until
    /// CueCan is reopened (TEST NEEDED on macOS 27; docs/design.md, "Open questions and checks").
    public static func status(of kind: AccessKind) -> AccessStatus {
        switch kind {
        case .camera: status(of: AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: status(of: AVCaptureDevice.authorizationStatus(for: .audio))
        case .screenRecording: ScreenCapture.hasPermission ? .allowed : .undecided
        case .accessibility: AXIsProcessTrusted() ? .allowed : .undecided
        }
    }

    static func status(of status: AVAuthorizationStatus) -> AccessStatus {
        switch status {
        case .authorized: .allowed
        case .notDetermined: .undecided
        default: .denied
        }
    }

    /// Asks macOS, which shows its own prompt and adds CueCan to the kind's list in System Settings.
    ///
    /// Camera and microphone return once the prompt is answered. The other two return at once: their prompt
    /// only offers to open System Settings, where the switch is.
    @MainActor
    public static func prompt(for kind: AccessKind) async {
        switch kind {
        case .camera: _ = await CaptureDevices.requestAccess(for: .video)
        case .microphone: _ = await CaptureDevices.requestAccess(for: .audio)
        case .screenRecording: ScreenCapture.requestPermission()
        case .accessibility: WindowSnapper.requestAccess()
        }
    }
}

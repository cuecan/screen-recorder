import Foundation

/// Whether a recording can start now, and if not, why (docs/ui.md, R2, R6 and R9).
///
/// The camera and the mic must be ready first: if the permission prompts were still open when the take
/// ended, the take would record without them, and the previews would come alive afterwards as if they were
/// being recorded.
public struct StartConditions: Sendable, Equatable {
    /// The setup bar is open, with nothing starting or recording.
    public var isSettingUp: Bool
    public var hasFormat: Bool
    /// A screen is picked, rather than No screen. Only then is an area needed.
    public var recordsScreen: Bool
    public var hasArea: Bool
    /// The camera is on, which a recording with no screen needs: otherwise there'd be no picture.
    public var hasCamera: Bool
    /// The camera and the mic have been asked for and chosen, for this setup.
    public var devicesReady: Bool
    /// The chosen camera is sending a picture (``CameraFrameWatch``). A camera that's on but sends nothing
    /// would leave the take without it.
    public var cameraHasPicture: Bool

    public init(isSettingUp: Bool, hasFormat: Bool, recordsScreen: Bool = true, hasArea: Bool, hasCamera: Bool = true, devicesReady: Bool,
                cameraHasPicture: Bool = true) {
        self.isSettingUp = isSettingUp
        self.hasFormat = hasFormat
        self.recordsScreen = recordsScreen
        self.hasArea = hasArea
        self.hasCamera = hasCamera
        self.devicesReady = devicesReady
        self.cameraHasPicture = cameraHasPicture
    }

    public var canStart: Bool { blocker == nil }

    /// What the dimmed Start button says on hover. Nil when it can start.
    public var blocker: String? {
        if !isSettingUp { return "The recording is starting" }
        if !hasFormat || (recordsScreen && !hasArea) { return "Pick where you’ll post it first" }
        if !devicesReady { return "Getting the camera and mic ready" }
        if !recordsScreen && !hasCamera { return "With no screen, pick a camera to record" }
        if hasCamera && !cameraHasPicture { return "Waiting for the camera’s picture" }
        return nil
    }

    /// What the setup element's title bar says in place of "Ready" and the format while it can't start
    /// (docs/ui.md, R10; Claude's proposal, AUTHOR'S TAKE NEEDED): the blocker, as a statement rather than a
    /// hint, such as "Pick where you’ll post it". Nil when it can start.
    public var headline: String? {
        guard let blocker else { return nil }
        return blocker.hasSuffix(" first") ? String(blocker.dropLast(" first".count)) : blocker
    }
}

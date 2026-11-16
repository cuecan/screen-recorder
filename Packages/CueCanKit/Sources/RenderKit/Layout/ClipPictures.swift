import CoreGraphics
import Foundation
import ProjectKit

/// The pictures a clip's source has, with their sizes in pixels.
public struct ClipPictures: Equatable, Sendable {
    public var screen: CGSize?
    public var camera: CGSize?
    public var video: CGSize?
    /// How the camera is framed in each kind of slot. Only the camera is framed; a screen or imported
    /// picture isn't.
    public var cameraFramings: CameraFramings
    /// The layout the take was set up with, which ``Layout/automatic`` means.
    public var recordedLayout: TakeLayout?
    /// The recorded area's height in points, which sets the screen's corners: a macOS window's, in the
    /// recording's own scale (``LayoutGeometry/windowCornerRadius``).
    public var screenPointHeight: Double?

    public init(screen: CGSize? = nil, camera: CGSize? = nil, video: CGSize? = nil, cameraFramings: CameraFramings = CameraFramings(),
                recordedLayout: TakeLayout? = nil, screenPointHeight: Double? = nil) {
        self.screen = screen
        self.camera = camera
        self.video = video
        self.cameraFramings = cameraFramings
        self.recordedLayout = recordedLayout
        self.screenPointHeight = screenPointHeight
    }

    /// The pictures of a source, from its probed tracks. A recorded area's screen takes the area's exact
    /// shape, because that's what the layouts are built around.
    public init(source: Source, cameraFramings: CameraFramings = CameraFramings()) {
        func size(_ kind: SourceTrack.Kind) -> CGSize? {
            source.track(kind)?.media.video.map { CGSize(width: $0.width, height: $0.height) }
        }
        var screen = size(.screen)
        if let area = source.captureArea, let recorded = screen {
            // An area's width is rounded to whole points, so its pixels are a hair off the ratio.
            screen = CGSize(width: recorded.height * area.ratio.aspect, height: recorded.height)
        }
        self.init(screen: screen, camera: size(.camera), video: size(.video), cameraFramings: cameraFramings, recordedLayout: source.layout,
                  screenPointHeight: source.captureArea.map { Double($0.heightPoints) })
    }

    /// The framing for a picture in a slot: the camera's for that slot, none for anything else.
    func framing(for role: PictureRole, slot: CameraSlot) -> CameraFraming? {
        role == .camera ? cameraFramings.framing(for: slot) : nil
    }

    /// The camera's framing in a slot.
    func cameraFraming(_ slot: CameraSlot) -> CameraFraming {
        cameraFramings.framing(for: slot)
    }

    /// The person: the camera for a screen recording, otherwise the imported picture.
    public var person: (role: PictureRole, size: CGSize)? {
        if let camera { return (.camera, camera) }
        if let video { return (.video, video) }
        return nil
    }

    /// The main picture: the screen for a screen recording, otherwise the imported picture or the camera.
    var main: (role: PictureRole, size: CGSize)? {
        if let screen { return (.screen, screen) }
        if let video { return (.video, video) }
        if let camera { return (.camera, camera) }
        return nil
    }
}

import CoreGraphics
import ProjectKit
import Foundation

/// How round each corner of a tile is, in pixels, from the top left going clockwise. Corners are drawn with
/// continuous curvature (``TileShape``).
public struct Corners: Equatable, Hashable, Sendable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// Every corner the same.
    public init(all radius: Double) {
        self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }

    public static let square = Corners(all: 0)

    /// The corners as a list, from the top left going clockwise.
    public var all: [Double] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Whether every corner is square, or near enough that drawing one would show nothing.
    public var isSquare: Bool { all.allSatisfy { $0 <= 0.5 } }

    /// The same corners after a mirror left to right.
    public var mirroredAcross: Corners { Corners(topLeft: topRight, topRight: topLeft, bottomRight: bottomLeft, bottomLeft: bottomRight) }

    /// The same corners after a mirror top to bottom.
    public var mirroredDown: Corners { Corners(topLeft: bottomLeft, topRight: bottomRight, bottomRight: topRight, bottomLeft: topLeft) }

    /// Each corner kept to half the shorter side of a frame, so they never overlap.
    func limited(to size: CGSize) -> Corners {
        let most = min(size.width, size.height) / 2
        return Corners(topLeft: min(topLeft, most), topRight: min(topRight, most), bottomRight: min(bottomRight, most), bottomLeft: min(bottomLeft, most))
    }
}

/// One picture drawn into an output frame.
public struct Placement: Equatable, Sendable {
    public var role: PictureRole
    /// The part of the source picture shown, as fractions of its width and height, from the top left.
    public var crop: CGRect
    /// Where it's drawn in the output frame, in pixels, from the top left.
    public var frame: CGRect
    /// How round its corners are, in pixels.
    public var corners: Corners
    /// Whether the picture is flipped left to right: the camera, when the look's Mirror is on.
    public var mirrored: Bool
    /// For the camera, the kind of slot it's in, whose framing cropped it. Nil for other pictures.
    public var cameraSlot: CameraSlot?
    /// The hairline drawn just inside the outline, in pixels: every camera's beside or over the screen. Zero
    /// draws none.
    public var borderWidth: Double

    public init(role: PictureRole, crop: CGRect, frame: CGRect, corners: Corners = .square, mirrored: Bool = false,
                cameraSlot: CameraSlot? = nil, borderWidth: Double = 0) {
        self.role = role
        self.crop = crop
        self.frame = frame
        self.corners = corners
        self.mirrored = mirrored
        self.cameraSlot = cameraSlot
        self.borderWidth = borderWidth
    }

    /// The corners as drawn: each kept to half the frame's shorter side.
    public var outlineCorners: Corners { corners.limited(to: frame.size) }
}

import CoreGraphics
import ProjectKit

/// A framing drag owns its starting point and framing only between mouse down and mouse up.
/// Coordinates arrive from an unflipped AppKit view; framing is measured from the picture's top left.
public enum FramingDrag: Equatable, Sendable {
    case idle
    case dragging(origin: CGPoint, framing: CameraFraming, mirrored: Bool)

    /// The framing at the pointer, or nil for a drag event without a matching mouse down.
    public func framing(at point: CGPoint, in size: CGSize) -> CameraFraming? {
        guard case .dragging(let origin, let framing, let mirrored) = self,
              size.width > 0, size.height > 0 else { return nil }
        let dx = (point.x - origin.x) / size.width
        let dy = (point.y - origin.y) / size.height
        return CameraFraming(centerX: framing.centerX + (mirrored ? -dx : dx),
                             centerY: framing.centerY - dy, zoom: framing.zoom)
    }
}

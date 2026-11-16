import Foundation

/// Where the camera is framed: a point and a zoom (docs/ui.md, R8; docs/decisions.md, 52).
///
/// The recording keeps the whole camera frame. The renderer crops every camera slot around this point
/// instead of the middle, each slot keeping its own shape, so the framing can be changed after the take,
/// by the creator or by Claude. It lives in the edit, so it's snapshotted and undone like any other change.
public struct CameraFraming: Codable, Equatable, Sendable {
    /// The point to frame around, as fractions of the camera's picture as recorded (not mirrored), from
    /// its top left.
    public let centerX: Double
    public let centerY: Double
    /// How far in: 1 shows as much of the camera as each slot's shape allows, 3 a third of that.
    public let zoom: Double

    public static let zoomRange: ClosedRange<Double> = 1...3

    /// The middle of the picture, not zoomed: what every camera slot showed before framing existed.
    public static let centered = CameraFraming(centerX: 0.5, centerY: 0.5, zoom: 1)

    /// A framing, with the point kept on the picture and the zoom in ``zoomRange``.
    public init(centerX: Double, centerY: Double, zoom: Double) {
        self.centerX = centerX.isNaN ? 0.5 : min(max(centerX, 0), 1)
        self.centerY = centerY.isNaN ? 0.5 : min(max(centerY, 0), 1)
        self.zoom = zoom.isNaN ? 1 : min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// Changes only the zoom, keeping the point and the value's bounds intact.
    public func zoomed(to zoom: Double) -> Self {
        Self(centerX: centerX, centerY: centerY, zoom: zoom)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            centerX: try container.decode(Double.self, forKey: .centerX),
            centerY: try container.decode(Double.self, forKey: .centerY),
            zoom: try container.decode(Double.self, forKey: .zoom)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case centerX, centerY, zoom
    }

    public var isCentered: Bool { self == .centered }
}

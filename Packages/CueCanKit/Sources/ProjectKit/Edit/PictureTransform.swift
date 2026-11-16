import Foundation

/// A static crop for one picture in a clip. The centre is a fraction of the original picture, from
/// its top left; zoom 1 shows as much as the layout allows. There are no keyframes or animated moves.
/// A camera transform overrides the take's slot framing for this clip alone.
public struct PictureTransform: Codable, Equatable, Hashable, Sendable {
    public let centerX: Double
    public let centerY: Double
    public let zoom: Double

    public static let zoomRange: ClosedRange<Double> = 1...3
    public static let identity = PictureTransform(centerX: 0.5, centerY: 0.5, zoom: 1)

    public init(centerX: Double = 0.5, centerY: Double = 0.5, zoom: Double = 1) {
        self.centerX = centerX.isFinite ? min(1, max(0, centerX)) : 0.5
        self.centerY = centerY.isFinite ? min(1, max(0, centerY)) : 0.5
        self.zoom = zoom.isFinite ? min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom)) : 1
    }

    /// Starts a clip's camera controls at the take's current framing, without changing the take.
    public init(_ framing: CameraFraming) {
        self.init(centerX: framing.centerX, centerY: framing.centerY, zoom: framing.zoom)
    }

    /// Uses the same bounded crop geometry as the recording's camera framing.
    public var framing: CameraFraming { CameraFraming(centerX: centerX, centerY: centerY, zoom: zoom) }

    public func changing(centerX: Double? = nil, centerY: Double? = nil, zoom: Double? = nil) -> Self {
        Self(centerX: centerX ?? self.centerX, centerY: centerY ?? self.centerY, zoom: zoom ?? self.zoom)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(centerX: try values.decode(Double.self, forKey: .centerX),
                  centerY: try values.decode(Double.self, forKey: .centerY),
                  zoom: try values.decode(Double.self, forKey: .zoom))
    }

    private enum CodingKeys: String, CodingKey { case centerX, centerY, zoom }
}

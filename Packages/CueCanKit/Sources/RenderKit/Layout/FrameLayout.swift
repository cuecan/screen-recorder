import CoreGraphics
import Foundation
import ProjectKit

/// What one output frame shows for a clip: its pictures, back to front, on the look's background.
public struct FrameLayout: Equatable, Sendable {
    public var output: OutputShape
    /// The frame's size in pixels.
    public var size: CGSize
    /// Drawn in order, so the first is at the back.
    public var placements: [Placement]
    /// The plain colour behind the pictures, as `#RRGGBB`.
    public var background: String

    public init(output: OutputShape, size: CGSize, placements: [Placement], background: String = "#000000") {
        self.output = output
        self.size = size
        self.placements = placements
        self.background = background
    }

    /// The placement of a role, if the frame shows it.
    public func placement(_ role: PictureRole) -> Placement? {
        placements.first { $0.role == role }
    }
}

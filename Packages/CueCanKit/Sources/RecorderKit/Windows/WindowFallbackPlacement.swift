import CoreGraphics
import Foundation

/// Keeps a window useful in the recording even when it cannot take the area's exact size.
public struct WindowFallbackPlacement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case centered, upperLeft }
    public let frame: CGRect
    public let kind: Kind

    /// Coordinates are global AppKit points. Smaller windows stay near the center, moving only as far
    /// as needed to reduce camera overlap. A window larger in either dimension starts at the upper left.
    public init(size: CGSize, in area: CGRect, avoiding cameras: [CGRect] = []) {
        guard size.width <= area.width + WindowFit.tolerance, size.height <= area.height + WindowFit.tolerance else {
            frame = CGRect(x: area.minX, y: area.maxY - size.height, width: size.width, height: size.height)
            kind = .upperLeft
            return
        }
        kind = .centered
        let center = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        let cameras = cameras.map { $0.intersection(area) }.filter { !$0.isNull && !$0.isEmpty }
        var xs = [center.x, area.minX, area.maxX - size.width]
        var ys = [center.y, area.minY, area.maxY - size.height]
        for camera in cameras {
            xs += [camera.minX - size.width - 8, camera.maxX + 8]
            ys += [camera.minY - size.height - 8, camera.maxY + 8]
        }
        var best = CGRect(origin: center, size: size)
        func overlap(_ frame: CGRect) -> CGFloat {
            cameras.reduce(0) { sum, camera in
                let intersection = camera.intersection(frame)
                return sum + (intersection.isNull ? 0 : intersection.width * intersection.height)
            }
        }
        func distance(_ frame: CGRect) -> CGFloat {
            pow(frame.minX - center.x, 2) + pow(frame.minY - center.y, 2)
        }
        for x in xs {
            for y in ys {
                let candidate = CGRect(x: min(max(x, area.minX), area.maxX - size.width),
                                       y: min(max(y, area.minY), area.maxY - size.height), width: size.width, height: size.height)
                let covered = overlap(candidate), previous = overlap(best)
                if covered < previous || (covered == previous && distance(candidate) < distance(best)) { best = candidate }
            }
        }
        frame = best
    }
}

import CoreGraphics
import Foundation
import ProjectKit

/// The numbers behind the base looks and their add-ons (a spike: docs/decisions.md, 81).
/// Daylight moves the light, and Aura and Glow lay a bloom of the camera's own colours behind the tiles; the
/// add-ons are shadows and a lit edge. Everything is a plain function of the edit's time, so the preview, stills and export
/// draw the same thing and motion runs on across cuts. Lengths are fractions of the panel's short side.
/// Every value is a starting point, to judge by eye (AUTHOR'S TAKE NEEDED).
public enum TileShadow {
    /// One layer of a tile's shadow: how soft, how far it falls (x to the right, y down) and how dark.
    public struct Layer: Equatable, Sendable {
        public var blur: Double
        public var x: Double, y: Double
        public var opacity: Double
    }

    /// The shadow's colour: a cool near-black on white, black on near-black.
    public static func color(dark: Bool) -> (red: Double, green: Double, blue: Double) {
        dark ? (0, 0, 0) : (0.08, 0.11, 0.18)
    }

    /// How far the wide shadow falls when the light is still.
    public static let fall = 0.022
    /// How far Daylight's light swings the shadow to either side, and how much its fall grows and shrinks.
    public static let swing = 0.03, lift = 0.01
    /// Seconds for Daylight's light to cross and come back.
    public static let daylightPeriod = 60.0

    /// Where Daylight's light is at a moment, from -1 (far left) to 1 (far right).
    public static func lightPosition(at time: Double) -> Double { -sin(2 * .pi * time / daylightPeriod) }

    /// A tile's two shadows at a moment, the wide one first: a wide soft one that gives it height, and a tight
    /// one where it meets the page. With `moving`, the wide one falls away from Daylight's light.
    public static func layers(dark: Bool, moving: Bool, at time: Double) -> [Layer] {
        let light = moving ? lightPosition(at: time) : 0
        let phase = 2 * .pi * time / daylightPeriod
        return [
            Layer(blur: 0.03, x: -light * swing, y: fall + (moving ? lift * cos(phase) : 0), opacity: dark ? 0.7 : 0.22),
            Layer(blur: 0.003, x: 0, y: 0.002, opacity: dark ? 0.5 : 0.1),
        ]
    }

}

/// The lit edge: a hairline around every tile, with a brighter line along its top where the light catches it.
public enum LitEdge {
    /// The hairline: faint and dark on a light background, faint and light on a dark one, as grey and opacity.
    public static func hairline(dark: Bool) -> (gray: Double, alpha: Double) { dark ? (1, 0.14) : (0.07, 0.09) }
    /// The top line's opacity, in white, and how far down the tile it fades out, as a fraction of its height.
    public static func highlight(dark: Bool) -> Double { dark ? 0.5 : 0.7 }
    public static let reach = 0.3
}

/// Daylight's warm band: a soft upright bar of warm light that crosses the white behind the tiles with the
/// light, like sun moving across a wall.
public enum DaylightBand {
    public static let color = (red: 1.0, green: 0.925, blue: 0.81)
    public static let opacity = 0.9
    /// The band's width and its blur, as fractions of the panel's width.
    public static let width = 0.2, blur = 0.1
    /// How far its centre travels either side of the middle, as a fraction of the panel's width.
    public static let reach = 0.34

    /// The band's centre at a moment, as a fraction of the panel's width from its left: under the light.
    public static func center(at time: Double) -> Double { 0.5 + reach * TileShadow.lightPosition(at: time) }
}

/// Aura's and Glow's bloom: the camera's picture (or with no camera, every tile's) blurred until only its colours are left, behind the tiles,
/// washed with white for Aura and dimmed for Glow, breathing slowly.
public enum Bloom {
    /// The blur's radius as a fraction of the working picture's short side.
    public static let blurFraction = 0.22
    /// Colours a little stronger than the pictures', since blurring greys them.
    public static let saturation = 1.8
    /// How much of the background's own colour is laid back over the bloom: white for Aura, so it stays pale;
    /// near-black for Glow, so a white screen doesn't flood it.
    public static func wash(dark: Bool) -> Double { dark ? 0.2 : 0.12 }
    /// How much the wash rises and falls as it breathes, and the seconds for one breath.
    public static let breath = 0.08, breathPeriod = 24.0
    /// The short side the blur is worked out at, in pixels, before it's scaled up to the panel.
    public static let workingShortSide = 180.0

    /// The wash at a moment, from 0 to 1.
    public static func wash(dark: Bool, at time: Double) -> Double {
        wash(dark: dark) + breath * sin(2 * .pi * time / breathPeriod)
    }

    /// The size the blur is worked out at for a panel: its shape, with the short side at
    /// ``workingShortSide``, in whole pixels.
    public static func workingSize(for panel: CGSize) -> CGSize {
        let short = min(panel.width, panel.height)
        guard short > 0 else { return .zero }
        let scale = min(1, workingShortSide / short)
        return CGSize(width: max(1, (panel.width * scale).rounded()), height: max(1, (panel.height * scale).rounded()))
    }
}

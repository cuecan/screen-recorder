import CoreGraphics
import Foundation
import Testing
@testable import RenderKit

/// The presets' motion and Trace's path are plain functions of time (docs/decisions.md, 81).
@Suite struct BackdropTests {
    @Test func aStillPresetsShadowNeverMovesAndDaylightsMovesSlowly() {
        #expect(TileShadow.layers(dark: false, moving: false, at: 3) == TileShadow.layers(dark: false, moving: false, at: 40))
        let now = TileShadow.layers(dark: false, moving: true, at: 12), next = TileShadow.layers(dark: false, moving: true, at: 12 + 1.0 / 60)
        // A frame later the wide shadow has moved under a ten-thousandth of the short side: a tenth of a pixel at 1080p.
        #expect(abs(now[0].x - next[0].x) < 0.0001 && abs(now[0].y - next[0].y) < 0.0001)
        #expect(now[0].x != TileShadow.layers(dark: false, moving: true, at: 22)[0].x)
        // The tight shadow stays where the tile meets the page.
        #expect(now[1] == TileShadow.layers(dark: false, moving: false, at: 0)[1])
        // On near-black a shadow has to be much darker to show at all.
        #expect(TileShadow.layers(dark: true, moving: false, at: 0)[0].opacity > now[0].opacity)
    }

    @Test func theBloomBreathesAroundItsWash() {
        for dark in [false, true] {
            let values = stride(from: 0.0, through: Bloom.breathPeriod, by: 0.5).map { Bloom.wash(dark: dark, at: $0) }
            #expect(values.allSatisfy { $0 > 0 && $0 < 1 })
            #expect(abs((values.max() ?? 0) - Bloom.wash(dark: dark) - Bloom.breath) < 0.001)
        }
        #expect(Bloom.workingSize(for: CGSize(width: 1920, height: 1080)) == CGSize(width: 320, height: 180))
    }
}

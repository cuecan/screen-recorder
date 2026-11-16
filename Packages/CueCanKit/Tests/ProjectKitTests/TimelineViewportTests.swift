import Foundation
import Testing
@testable import ProjectKit

struct TimelineViewportTests {
    @Test func zoomKeepsAVisiblePlayheadAtTheSameScreenPosition() {
        let viewport = TimelineViewport(offset: 400, width: 800)
        let offset = viewport.offsetAfterZoom(from: 100, to: 200, playhead: 7, duration: 120)
        #expect(abs((10 + 7 * 200 - offset) - (10 + 7 * 100 - 400)) < 0.001)
    }

    @Test func zoomPreservesTheViewWhenThePlayheadIsElsewhere() {
        let viewport = TimelineViewport(offset: 4_000, width: 800)
        let offset = viewport.offsetAfterZoom(from: 100, to: 200, playhead: 1, duration: 120)
        #expect(abs((10 + 43.9 * 200 - offset) - 400) < 0.001)
    }

    @Test func revealingAnOffscreenEditKeepsContextAndVisibleTimesStayPut() {
        let viewport = TimelineViewport(offset: 400, width: 800)
        #expect(viewport.offsetRevealing(7, duration: 120, zoom: 100) == 400)
        #expect(viewport.offsetRevealing(20, duration: 120, zoom: 100) == 1_410)
        #expect(viewport.offsetRevealing(2, duration: 120, zoom: 100) == 10)
    }

    @Test func playbackPagesWithoutRecenteringEveryTick() {
        let viewport = TimelineViewport(offset: 0, width: 800)
        #expect(viewport.offsetRevealing(6, duration: 120, zoom: 100, playing: true) == 0)
        #expect(viewport.offsetRevealing(8, duration: 120, zoom: 100, playing: true) == 650)
    }

    @Test func fittingOrShorteningAProjectClampsTheScrollOffset() {
        let viewport = TimelineViewport(offset: 4_000, width: 800)
        #expect(viewport.clampedOffset(4_000, duration: 5, zoom: 100) == 0)
        #expect(viewport.clampedOffset(4_000, duration: 10, zoom: 100) == 260)
        #expect(viewport.clampedOffset(-20, duration: 120, zoom: 100) == 0)
    }

    @Test func waveformWorkIsLimitedToTheViewportAndItsGridIsStable() {
        let viewport = TimelineViewport(offset: 100_000, width: 1_000)
        let bars = Array(viewport.waveformBars(from: 10, to: 1_000_000))
        #expect(bars.count < 420)
        #expect(bars.allSatisfy { abs((($0 - 11) / 2.5).rounded() - ($0 - 11) / 2.5) < 0.000_001 })
        let shifted = Set(TimelineViewport(offset: 100_001, width: 1_000).waveformBars(from: 10, to: 1_000_000))
        #expect(Set(bars.dropFirst().dropLast()).isSubset(of: shifted))
        #expect(Array(viewport.waveformBars(from: 0, to: 50)).isEmpty)
    }

    @Test func invalidGeometryNeverProducesAnInvalidRangeOrOffset() {
        let viewport = TimelineViewport(offset: .nan, width: .infinity)
        #expect(viewport.offset == 0)
        #expect(viewport.width == 1)
        #expect(viewport.clampedOffset(.infinity, duration: 10, zoom: 100) == 0)
        #expect(viewport.timeRange(zoom: .nan).start == 0)
    }
}

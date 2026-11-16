import AppKit
import Testing
@testable import CueCan

@MainActor
struct PreviewPanelGeometryTests {
    @Test func fractionalViewSizesFillEveryEdgeOfThePanel() {
        for size in [CGSize(width: 687.5, height: 386.5), CGSize(width: 303.5, height: 540.25)] {
            for panel in [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                          CGRect(x: 1920, y: 0, width: 607.5, height: 1080)] {
                let view = PanelPlayerView(frame: CGRect(origin: .zero, size: size))
                view.panel = panel
                view.composition = CGSize(width: 2528, height: 1080)
                view.layout()
                let mapped = CGRect(x: view.playerLayer.frame.minX + panel.minX * size.width / panel.width,
                                    y: view.playerLayer.frame.minY + panel.minY * size.height / panel.height,
                                    width: panel.width * view.playerLayer.frame.width / view.composition.width,
                                    height: panel.height * view.playerLayer.frame.height / view.composition.height)
                #expect(abs(mapped.minX) < 0.000_001)
                #expect(abs(mapped.minY) < 0.000_001)
                #expect(abs(mapped.maxX - size.width) < 0.000_001)
                #expect(abs(mapped.maxY - size.height) < 0.000_001)
                #expect(view.posterLayer.frame == view.playerLayer.frame)
            }
        }
    }
}

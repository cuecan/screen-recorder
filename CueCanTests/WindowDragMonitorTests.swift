import Foundation
import Testing
@testable import CueCan

@MainActor
struct WindowDragMonitorTests {
    @Test func returningFromTheNativeDragDoesNotEndAHeldGesture() {
        var down = true
        var starts = 0, ends = 0
        let monitor = WindowDragMonitor(isButtonDown: { down }, began: { starts += 1 }, ended: { ends += 1 })
        monitor.start()
        monitor.checkForRelease()
        monitor.start()
        #expect(starts == 1 && ends == 0 && monitor.isTracking)
        down = false
        monitor.checkForRelease()
        monitor.checkForRelease()
        #expect(ends == 1 && !monitor.isTracking)
    }

    @Test func hidingAPanelBalancesAndInvalidatesItsDrag() {
        var starts = 0, ends = 0
        let monitor = WindowDragMonitor(isButtonDown: { true }, began: { starts += 1 }, ended: { ends += 1 })
        monitor.start()
        monitor.cancel()
        monitor.cancel()
        #expect(starts == 1 && ends == 1 && !monitor.isTracking)
        monitor.start()
        #expect(starts == 2 && monitor.isTracking)
        monitor.cancel()
        #expect(ends == 2)
    }
}

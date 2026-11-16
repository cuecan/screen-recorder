import AppKit
import Testing
@testable import CueCan

@MainActor
@Suite(.serialized)
struct MenuAnchorTests {
    private let entries: [MenuEntry] = [.item("A source", action: {})]

    @Test func presentationReturnsBeforeTrackingAndCoalescesRepeatedPresses() async {
        let (window, view) = makeWindow()
        defer { window.close() }
        var presentations = 0
        let anchor = MenuAnchor { _, _, _ in presentations += 1 }
        anchor.attach(to: view)
        defer { anchor.detach(from: view) }

        anchor.open(entries)
        anchor.open(entries)
        #expect(presentations == 0)
        await nextRunLoopTurn()
        #expect(presentations == 1)

        anchor.open(entries)
        await nextRunLoopTurn()
        #expect(presentations == 2)
    }

    @Test func anotherPickerCannotStartNestedTracking() async {
        let (window, view) = makeWindow()
        defer { window.close() }
        var secondPresentations = 0
        let second = MenuAnchor { _, _, _ in secondPresentations += 1 }
        second.attach(to: view)
        let first = MenuAnchor { _, _, _ in second.open(entries) }
        first.attach(to: view)
        defer { first.detach(from: view); second.detach(from: view) }

        first.open(entries)
        await nextRunLoopTurn()
        await nextRunLoopTurn()
        #expect(secondPresentations == 0)

        second.open(entries)
        await nextRunLoopTurn()
        #expect(secondPresentations == 1)
    }

    @Test func detachedPendingRequestDoesNotPresentOrCancelItsReplacement() async {
        let (window, view) = makeWindow()
        defer { window.close() }
        var presentations = 0
        let anchor = MenuAnchor { _, _, _ in presentations += 1 }
        anchor.attach(to: view)
        defer { anchor.detach(from: view) }

        anchor.open(entries)
        anchor.detach(from: view)
        anchor.attach(to: view)
        anchor.open(entries)
        await nextRunLoopTurn()
        #expect(presentations == 1)
    }

    @Test func closingWindowBeforeScheduledPresentationCancelsIt() async {
        let (window, view) = makeWindow()
        defer { window.close() }
        var presentations = 0
        let anchor = MenuAnchor { _, _, _ in presentations += 1 }
        anchor.attach(to: view)
        defer { anchor.detach(from: view) }

        anchor.open(entries)
        window.orderOut(nil)
        await nextRunLoopTurn()
        #expect(presentations == 0)

        window.orderFront(nil)
        anchor.open(entries)
        await nextRunLoopTurn()
        #expect(presentations == 1)
    }

    @Test func trackingLoopCanServiceMainQueueWork() async {
        let (window, view) = makeWindow()
        defer { window.close() }
        var servicedMainQueue = false
        let anchor = MenuAnchor { _, _, _ in
            DispatchQueue.main.async { servicedMainQueue = true }
            let deadline = Date().addingTimeInterval(1)
            while !servicedMainQueue, Date() < deadline {
                RunLoop.current.run(mode: .default, before: deadline)
            }
            #expect(servicedMainQueue)
        }
        anchor.attach(to: view)
        defer { anchor.detach(from: view) }

        anchor.open(entries)
        await nextRunLoopTurn()
        #expect(servicedMainQueue)
    }

    private func makeWindow() -> (NSWindow, NSView) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 24),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 80, height: 24))
        window.contentView = view
        window.orderFront(nil)
        return (window, view)
    }

    private func nextRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
    }
}

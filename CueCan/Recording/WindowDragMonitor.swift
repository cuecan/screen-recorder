import AppKit

/// Window-server dragging returns immediately and may consume mouse-up. Watch the physical button in
/// common run-loop modes so window owners can defer layout and persistence until the actual release.
@MainActor
final class WindowDragMonitor {
    private let isButtonDown: () -> Bool
    private let began: () -> Void
    private let ended: () -> Void
    private var timer: Timer?
    private(set) var isTracking = false

    init(isButtonDown: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 },
         began: @escaping () -> Void, ended: @escaping () -> Void) {
        self.isButtonDown = isButtonDown
        self.began = began
        self.ended = ended
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        began()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.checkForRelease()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func checkForRelease() {
        if isTracking, !isButtonDown() { cancel() }
    }

    /// Also balances a drag if its panel is hidden before release.
    func cancel() {
        timer?.invalidate()
        timer = nil
        guard isTracking else { return }
        isTracking = false
        ended()
    }
}

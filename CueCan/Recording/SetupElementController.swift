import AppKit
import Observation
import RecorderKit
import SwiftUI

/// The setup element's window (docs/ui.md, R10; docs/decisions.md, 79): one window while setting up, the
/// live preview over the strip. It starts at the bottom centre of the area's display the first time, then
/// where it was last put on that display. The strip stays put as the preview's height changes. On Record it
/// hands over to the Recording Panel as the take starts.
@Observable
final class SetupElementController {
    @ObservationIgnored private unowned let recorder: RecorderModel
    @ObservationIgnored private var panel: OverlayPanel?
    @ObservationIgnored private var moveObserver: (any NSObjectProtocol)?
    /// The element is being placed by CueCan, not dragged by the creator.
    @ObservationIgnored private var isPlacing = false
    @ObservationIgnored private var isDragging = false
    /// Where the element was when the hand-over began, to come back to if the start fails.
    @ObservationIgnored private var frameBeforeHandOver: CGRect?
    /// The preview's tiles, and the main camera slot's tile, in the window's coordinates (top left origin),
    /// for the hand-over to send into the panel's picture.
    @ObservationIgnored var previewFrameInWindow: CGRect?
    @ObservationIgnored var cameraFrameInWindow: CGRect?

    /// The visible height of the element's display, which caps the preview on a short one.
    private(set) var visibleHeight: Double = 10_000
    /// On Record the strip drops away (R10, "The hand-over at Record").
    private var handover = SetupHandover()
    var isLeaving: Bool { handover.isLeaving }

    @ObservationIgnored private var places: SetupElementPlaces {
        didSet {
            if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: Self.placesKey) }
        }
    }
    private static let placesKey = "setupElementPlaces"

    init(recorder: RecorderModel) {
        self.recorder = recorder
        places = UserDefaults.standard.data(forKey: Self.placesKey).flatMap { try? JSONDecoder().decode(SetupElementPlaces.self, from: $0) }
            ?? SetupElementPlaces()
    }

    var isShowing: Bool { panel?.isVisible ?? false }
    /// The element's frame, while it shows.
    var frame: CGRect? { isShowing ? panel?.frame : nil }
    /// The display the element is on.
    var screen: NSScreen? { panel.flatMap { NSScreen.holding($0.frame) } }

    func show() {
        if let panel {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        handover.cancel()
        let screen = NSScreen.with(id: recorder.area.selectedDisplayID) ?? NSScreen.underPointer
        let visible = screen?.visibleFrame ?? .zero
        visibleHeight = visible.height
        let panel = OverlayPanel.hosting(SetupElementView(recorder: recorder, element: self), level: .captureControls, takesKeyboard: true)
        panel.title = "New recording"
        panel.onUserDragStarted = { [weak self] in self?.dragStarted() }
        panel.onUserDragEnded = { [weak self] in self?.dragEnded() }
        self.panel = panel
        let size = panel.fittingSize
        let remembered = screen.flatMap { screen in
            screen.persistentID.flatMap { places.frame(on: $0, size: size, displayFrame: screen.frame, visible: visible) }
        }
        place(remembered ?? SetupElementPlacement.first(size: size, area: recorder.area.placement?.frame, display: visible))
        panel.orderFrontRegardless()
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }
    }

    /// Gives the element the keyboard, so Esc and Return reach it.
    func focus() {
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Closes the element. It comes back where it was put, next time, on that display.
    func hide() {
        panel?.orderOut(nil)
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel = nil
        handover.cancel()
        frameBeforeHandOver = nil
    }

    /// The content changed height, such as the format or the Layout menu changing the well: the strip
    /// stays put and the well grows upward, or the element moves down when there's no room above.
    func contentSizeChanged(_ size: CGSize) {
        guard let panel, !isLeaving, !isDragging, size.width > 0, size.height > 0, panel.frame.size != size else { return }
        let visible = (NSScreen.holding(panel.frame) ?? NSScreen.main)?.visibleFrame ?? panel.frame
        place(SetupElementPlacement.resized(panel.frame, toHeight: size.height, within: visible))
    }

    /// While a window is dragged onto the area, the element fades, so it doesn't block the snap (R10;
    /// Claude's proposal, AUTHOR'S TAKE NEEDED). It comes back on release.
    func setFaded(_ faded: Bool) {
        guard let panel, !isLeaving else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = faded ? 0.12 : 1
        }
        panel.ignoresMouseEvents = faded
    }

    // MARK: - The hand-over at Record

    /// Hands the element over to the Recording Panel inside "3" (R10; Claude's proposal, AUTHOR'S TAKE NEEDED):
    /// for 0.2 s the strip slides down and fades; then, for 0.4 s, the element travels so its preview's
    /// middle lands on the panel's picture (for Camera only, its main camera tile on the panel's square)
    /// while fading, and the panel fades in there, in the view and at the width last used on this display
    /// (docs/decisions.md, 82). With the panel Hidden, the element fades where it is. Nothing moves after
    /// that.
    ///
    /// - Parameter showPanel: Shows the Recording Panel, see-through, on the element's display, and gives
    ///   back its window, its picture's frame on screen and whether it shows the camera alone, or nil when
    ///   it's Hidden.
    func handOver(showPanel: @escaping (NSScreen?) -> (window: NSWindow, picture: CGRect, showsCamera: Bool)?) {
        guard let panel else { return }
        frameBeforeHandOver = panel.frame
        let request = withAnimation(.easeIn(duration: 0.2)) { handover.begin() }
        let screen = self.screen
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, self.panel === panel, self.handover.accepts(request, phase: self.recorder.phase) else { return }
            let shown = showPanel(screen)
            let recording = shown?.window
            var travelled = panel.frame
            if let shown {
                // The preview's middle, or Camera only's camera tile, travels to the panel's picture.
                let source = (shown.showsCamera ? self.cameraFrameInWindow : nil) ?? self.previewFrameInWindow
                let onScreen = source.map { CGRect(x: panel.frame.minX + $0.minX, y: panel.frame.maxY - $0.maxY, width: $0.width, height: $0.height) }
                    ?? panel.frame
                travelled.origin.x += (shown.picture.midX - onScreen.midX).rounded()
                travelled.origin.y += (shown.picture.midY - onScreen.midY).rounded()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.isPlacing = true
                panel.animator().setFrame(travelled, display: true)
                panel.animator().alphaValue = 0
                recording?.animator().alphaValue = 1
            } completionHandler: {
                MainActor.assumeIsolated {
                    self.isPlacing = false
                    guard self.panel === panel, self.handover.accepts(request, phase: self.recorder.phase) else { return }
                    panel.orderOut(nil)
                    if self.handover.animationFinished(request, phase: self.recorder.phase) { self.hide() }
                }
            }
        }
    }

    /// The start failed before the take began: the element comes back as it was.
    func comeBack() {
        guard let panel else { return }
        handover.cancel()
        if let frameBeforeHandOver { place(frameBeforeHandOver) }
        frameBeforeHandOver = nil
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    /// Release the hidden setup's camera layers and screen-preview viewer after a successful hand-over.
    func recordingStarted() {
        if handover.canRetireAfterRecordingStarted { hide() }
    }

    // MARK: - Placing

    private func place(_ frame: CGRect) {
        guard let panel else { return }
        isPlacing = true
        panel.setFrame(frame, display: true)
        isPlacing = false
        remember()
    }

    private func moved() {
        guard !isDragging, let panel, let screen = NSScreen.holding(panel.frame) else { return }
        if visibleHeight != screen.visibleFrame.height { visibleHeight = screen.visibleFrame.height }
        if !isPlacing, !isLeaving { remember() }
    }

    /// Let AppKit own the whole drag. Display-driven resizing and preference writes wait for release.
    private func dragStarted() { isDragging = true }

    private func dragEnded() {
        isDragging = false
        moved()
        if let panel { contentSizeChanged(panel.fittingSize) }
    }

    private func remember() {
        guard let panel, !isLeaving, let screen = NSScreen.holding(panel.frame), let id = screen.persistentID else { return }
        places.remember(panel.frame, on: id, displayFrame: screen.frame)
    }
}

import AppKit
import Observation
import ProjectKit
import RecorderKit
import RenderKit
import SwiftUI

/// The capture area on the desktop (docs/ui.md, R2 to R5; docs/decisions.md, 19 to 21): a frame of the
/// format's shape with a 2 pt outline and corner handles outside it, the outside dimmed, and a capsule in
/// its middle with the move handle and Start recording. Everywhere else inside the area, clicks reach the
/// window underneath. A window dragged onto it is snapped in to fill it.
@Observable
final class CaptureAreaController {
    /// Where the area is in the recording's life.
    enum Stage {
        case setup, starting, recording
    }

    /// The notice at the frame after a drop (docs/ui.md, R4). Each case carries what its buttons need.
    enum SnapNotice: Equatable {
        /// Moving other apps' windows needs Device Control and Data Access (Accessibility before macOS 27).
        case needsAccess(appName: String)
        /// The window couldn't be moved at all. It says full screen only when the window is.
        case cannotMove(appName: String, isFullScreen: Bool)
        /// The window was placed at its observed size. A larger area can still be offered during setup.
        case doesNotFit(window: SnappableWindow, fit: WindowFit, placement: WindowFallbackPlacement.Kind, biggerArea: CaptureArea?)

        var message: String {
            switch self {
            // One short line each: no sizes, and nothing the window's new place already shows.
            case .needsAccess(let app):
                "To snap \(app) in, allow CueCan in \(CaptureAreaController.windowAccessPaneName) settings."
            case .cannotMove(let app, let isFullScreen):
                isFullScreen ? "\(app) is full screen. Exit full screen, then drag it in again."
                    : "\(app) couldn’t be moved. Try dragging it in again."
            case .doesNotFit(let window, let fit, _, _):
                fit.notice(appName: window.appName) ?? ""
            }
        }

        /// Whether a bigger area could help: only when the window is too big, not when it can't grow.
        var offersBiggerArea: Bool {
            guard case .doesNotFit(_, let fit, _, _) = self else { return false }
            switch fit {
            case .tooNarrow, .tooShort: return true
            case .tooSlim, .tooLow, .fits: return false
            }
        }
    }

    @ObservationIgnored private unowned let recorder: RecorderModel
    @ObservationIgnored let snapper = WindowSnapper()
    @ObservationIgnored private let dragWatcher = WindowDragWatcher()
    @ObservationIgnored private var displayObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var switchObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var snappingTask: Task<Void, Never>?
    @ObservationIgnored private var snapRequest = UUID()

    @ObservationIgnored private var dimming: [OverlayPanel] = []
    @ObservationIgnored private var edges: [(panel: OverlayPanel, view: AreaDragView)] = []
    @ObservationIgnored private var corners: [(panel: OverlayPanel, view: AreaDragView)] = []
    @ObservationIgnored private lazy var label = HostedPanel(level: .captureControls, passesClicksThrough: true)
    @ObservationIgnored private lazy var capsule = HostedPanel(level: .captureControls, passesClicksThrough: false, takesKeyboard: true)
    /// The shading where the camera will cover the screen (docs/decisions.md, 66).
    @ObservationIgnored private lazy var cover = HostedPanel(level: .captureDimming, passesClicksThrough: true)
    @ObservationIgnored private lazy var tint = OverlayPanel.filled(NSColor.controlAccentColor.withAlphaComponent(0.16), level: .captureDimming)
    @ObservationIgnored private lazy var release = HostedPanel(level: .captureControls, passesClicksThrough: true)
    @ObservationIgnored private lazy var willFill = HostedPanel(level: .captureControls, passesClicksThrough: true)
    @ObservationIgnored private lazy var noticePanel = HostedPanel(level: .captureControls, passesClicksThrough: false, takesKeyboard: true)

    private(set) var displays: [CaptureDisplay] = []
    private(set) var selectedDisplayID: CGDirectDisplayID?
    private(set) var placement: AreaPlacement?
    private(set) var isShowing = false
    private(set) var stage = Stage.setup
    /// The app whose window is being dragged over the area. The setup element fades meanwhile, so it doesn't
    /// block the snap (docs/ui.md, R10).
    private(set) var hovering: SnappableWindow? {
        didSet {
            if (hovering == nil) != (oldValue == nil) { recorder.element.setFaded(hovering != nil) }
        }
    }
    private(set) var notice: SnapNotice?

    init(recorder: RecorderModel) {
        self.recorder = recorder
        refreshDisplays()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
        dragWatcher.onChange = { [weak self] change in self?.dragChanged(change) }
    }

    /// The outline's width while setting up, outside the area; 4 pt while a window is dragged over it.
    static let outlineWidth: CGFloat = AreaGeometry.outlineWidth
    /// The quiet frame while recording.
    static let recordingOutlineWidth: CGFloat = 1
    /// How far outside the area an edge can be grabbed to move it.
    static let edgeGrab: CGFloat = 8

    // MARK: - Showing

    /// Shows the area in a shape on the chosen monitor, at the largest size that fits, centred
    /// (docs/decisions.md, 19). Windows snapped into the old area follow it.
    ///
    /// It fits the desktop, under the menu bar, unless the area was last left over the menu bar or the Dock
    /// on this monitor: then it fits the whole display.
    func show(ratio: CaptureArea.Ratio) {
        refreshDisplays()
        guard let screen = NSScreen.with(id: selectedDisplayID) ?? NSScreen.underPointer, let displayID = screen.displayID else { return }
        selectedDisplayID = displayID
        let visible = screen.visibleFrame
        let bounds = Self.reachedPastDesktop(on: screen) ? screen.frame : visible
        guard let largest = CaptureArea.largest(ratio, fittingWidth: bounds.width, height: bounds.height) else {
            recorder.problem = "No area of this shape fits this display."
            return
        }
        let old = placement?.frame
        let frame = AreaGeometry.centered(width: Double(largest.widthPoints), height: Double(largest.heightPoints), on: bounds)
        placement = AreaPlacement(area: largest, frame: frame, displayID: displayID, displayFrame: screen.frame, visibleFrame: visible)
        isShowing = true
        stage = .setup
        notice = nil
        startWatching()
        layout()
        if let old { followWindows(from: old) }
    }

    /// Takes the area away. Snapped windows stay where they are; CueCan forgets which apps had been in.
    func hide() {
        cancelSnapping()
        snapper.forgetAll()
        stopWatching()
        placement = nil
        isShowing = false
        stage = .setup
        hovering = nil
        notice = nil
        for panel in dimming + edges.map(\.panel) + corners.map(\.panel) { panel.orderOut(nil) }
        for panel in [label, capsule, release, willFill, noticePanel, cover] { panel.hide() }
        tint.orderOut(nil)
    }

    func refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return CaptureDisplay(id: id, name: screen.localizedName, width: Int(screen.frame.width), height: Int(screen.frame.height))
        }
        if !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = NSScreen.underPointer?.displayID ?? displays.first?.id
        }
    }

    /// Starts each setup on the display the pointer is on.
    func selectDisplayUnderPointer() {
        refreshDisplays()
        if let id = NSScreen.underPointer?.displayID { selectedDisplayID = id }
    }

    /// Records a different monitor: the area moves there at once (docs/decisions.md, 19).
    func chooseDisplay(_ id: CGDirectDisplayID) {
        guard stage == .setup, NSScreen.with(id: id) != nil else { return }
        selectedDisplayID = id
        if let ratio = placement?.area.ratio { show(ratio: ratio) }
        recorder.preview.areaChanged()
    }

    private func displaysChanged() {
        refreshDisplays()
        guard isShowing, stage == .setup, let placement else { return }
        if NSScreen.with(id: placement.displayID) == nil { selectedDisplayID = displays.first?.id }
        show(ratio: placement.area.ratio)
        recorder.preview.areaChanged()
    }

    // MARK: - The recording's stages

    func takeStarting() {
        cancelSnapping()
        stage = .starting
        hovering = nil
        notice = nil
        layout()
    }

    func startCancelled() {
        stage = .setup
        layout()
    }

    func recordingStarted() {
        stage = .recording
        layout()
    }

    /// The layout, its size or the camera's side changed: the shading follows.
    func coverChanged() {
        layout()
        if let placement { followWindows(from: placement.frame) }
    }

    // MARK: - Moving and sizing

    /// A corner or the handle dragged, from the frame the drag started with, so moving panels can't feed
    /// back into the gesture.
    func adjust(from original: CGRect, corner: AreaGeometry.Corner?, translation: CGSize) {
        guard stage == .setup, var placement else { return }
        if let corner {
            placement.frame = AreaSticking.resized(original, corner: corner, translation: translation, ratio: placement.area.ratio,
                                                   within: placement.visibleFrame, limit: placement.displayFrame)
            placement.area = CaptureArea(ratio: placement.area.ratio, heightPoints: Int(placement.frame.height))
        } else {
            placement.frame = AreaSticking.moved(original, by: translation, within: placement.visibleFrame, limit: placement.displayFrame)
        }
        guard placement != self.placement else { return }
        cancelSnapping()
        self.placement = placement
        notice = nil
        layout()
    }

    /// The sizes the capsule's menu offers on this display, largest first.
    var sizeChoices: [AreaChoice] {
        guard let placement else { return [] }
        return AreaChoice.offered(for: placement.area.ratio, desktop: placement.visibleFrame, display: placement.displayFrame)
    }

    /// The size the area is at, for the menu's tick. Nil for one dragged to in between.
    var sizeChoice: AreaChoice? {
        guard let placement else { return nil }
        return AreaChoice.matching(placement.frame, ratio: placement.area.ratio, desktop: placement.visibleFrame, display: placement.displayFrame)
    }

    /// A size picked from the capsule's menu.
    func choose(_ choice: AreaChoice) {
        guard stage == .setup, var placement,
              let frame = choice.frame(for: placement.area.ratio, from: placement.frame,
                                       desktop: placement.visibleFrame, display: placement.displayFrame),
              frame != placement.frame else { return }
        let old = placement.frame
        placement.frame = frame
        placement.area = CaptureArea(ratio: placement.area.ratio, heightPoints: Int(frame.height))
        cancelSnapping()
        self.placement = placement
        notice = nil
        rememberReach(of: placement)
        layout()
        followWindows(from: old)
        recorder.preview.areaChanged()
    }

    /// The drag ended: snapped windows follow the area, and the preview follows it too.
    func dragEnded(from original: CGRect) {
        guard let placement, placement.frame != original else { return }
        rememberReach(of: placement)
        followWindows(from: original)
        recorder.preview.areaChanged()
    }

    // MARK: - Over the menu bar

    /// The monitors where the area was last left over the menu bar or the Dock, by their lasting ids.
    private static let reachKey = "areaReachesPastDesktop"

    private static func reachedPastDesktop(on screen: NSScreen) -> Bool {
        guard let id = screen.persistentID else { return false }
        return (UserDefaults.standard.stringArray(forKey: reachKey) ?? []).contains(id)
    }

    /// Keeps whether the area is over the menu bar or the Dock, so the next setup on this monitor opens
    /// the same way.
    private func rememberReach(of placement: AreaPlacement) {
        guard let id = NSScreen.with(id: placement.displayID)?.persistentID else { return }
        var ids = Set(UserDefaults.standard.stringArray(forKey: Self.reachKey) ?? [])
        if placement.reachesPastDesktop { ids.insert(id) } else { ids.remove(id) }
        UserDefaults.standard.set(ids.sorted(), forKey: Self.reachKey)
    }

    // MARK: - Snapping windows

    private func startWatching() {
        dragWatcher.area = placement?.frame
        dragWatcher.start()
        guard switchObserver == nil else { return }
        switchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.appCameForward(pid)
            }
        }
    }

    private func stopWatching() {
        dragWatcher.stop()
        dragWatcher.area = nil
        if let switchObserver { NSWorkspace.shared.notificationCenter.removeObserver(switchObserver) }
        switchObserver = nil
    }

    /// An app that has been in the area snaps back in when the creator switches to it (docs/decisions.md, 21).
    private func appCameForward(_ pid: pid_t) {
        guard snapper.snappedApps.contains(pid) else { return }
        Task { [weak self] in
            // The app's focused window settles a moment after it activates.
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, let frame = self.placement?.windowFrame, self.stage != .starting, self.snappingTask == nil else { return }
            let request = self.snapRequest
            let result = await self.snapper.snapFocusedWindow(of: pid, to: frame, avoiding: self.cameraObstructions)
            guard !Task.isCancelled, self.snapRequest == request, self.placement?.windowFrame == frame,
                  self.stage != .starting,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            if case .placed = result,
               let window = WindowSnapper.windows().first(where: { $0.processID == pid }) {
                self.showSnapResult(result, for: window)
            }
        }
    }

    private func dragChanged(_ change: WindowDragTracker.Change) {
        guard isShowing, stage != .starting else { return }
        switch change {
        case .entered(let window):
            hovering = window
            notice = nil
        case .left:
            hovering = nil
        case .dropped(let window, _):
            hovering = nil
            snapIn(window)
        }
        layout()
    }

    /// The camera covers in every output, mapped from screen fractions to global AppKit coordinates.
    private var cameraObstructions: [CGRect] {
        guard recorder.isCameraOn, let placement, let format = recorder.format else { return [] }
        let area = placement.frame
        return format.outputs.compactMap { output in
            guard let cover = LayoutGeometry.cover(format.layout, shape: format.captureRatio, in: output, look: recorder.look) else { return nil }
            let rect = cover.rect
            return CGRect(x: area.minX + rect.minX * area.width, y: area.maxY - rect.maxY * area.height,
                          width: rect.width * area.width, height: rect.height * area.height)
        }
    }

    private func cancelSnapping() {
        snapRequest = UUID()
        snappingTask?.cancel()
        snappingTask = nil
        snapper.cancelPending()
    }

    private func snapIn(_ window: SnappableWindow) {
        guard let placement else { return }
        guard WindowSnapper.hasAccess else {
            WindowSnapper.requestAccess()
            notice = .needsAccess(appName: window.appName)
            return
        }
        cancelSnapping()
        let request = snapRequest, avoiding = cameraObstructions
        snappingTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.snapper.snap(window, to: placement.windowFrame, avoiding: avoiding)
            guard !Task.isCancelled, self.snapRequest == request, self.placement?.frame == placement.frame else { return }
            self.snappingTask = nil
            self.showSnapResult(result, for: window)
        }
    }

    private func showSnapResult(_ result: WindowSnapResult?, for window: SnappableWindow) {
        guard let placement else { return }
        switch result {
        case .filled:
            notice = nil
        case .placed(let fit, let frame, let kind):
            let minimum = kind == .upperLeft ? frame.size : nil
            let bigger = minimum.flatMap { AreaSticking.smallestArea(placement.area.ratio, holding: $0, display: placement.bounds) }
            notice = .doesNotFit(window: window, fit: fit, placement: kind, biggerArea: bigger)
        case nil:
            notice = .cannotMove(appName: window.appName, isFullScreen: snapper.lastFailure == .fullScreen)
        }
        layout()
    }

    private func followWindows(from old: CGRect, thenSnap window: SnappableWindow? = nil) {
        guard let placement else { return }
        cancelSnapping()
        let request = snapRequest, avoiding = cameraObstructions
        snappingTask = Task { [weak self] in
            guard let self else { return }
            // Windows were in the part of the old area that was on the desktop, and go to that part of the new.
            let oldWindows = AreaGeometry.windowFrame(in: old, desktop: placement.visibleFrame)
            await self.snapper.follow(from: oldWindows, to: placement.windowFrame, avoiding: avoiding)
            guard !Task.isCancelled, self.snapRequest == request else { return }
            if let window {
                let result = await self.snapper.snap(window, to: placement.windowFrame, avoiding: avoiding)
                guard !Task.isCancelled, self.snapRequest == request else { return }
                self.showSnapResult(result, for: window)
            }
            self.snappingTask = nil
        }
    }

    /// Makes the area big enough for the window that couldn't fit, then snaps it in.
    /// Only while setting up: during a recording the stream keeps the crop it started with, so the area
    /// must not change under it.
    func useBiggerArea() {
        guard stage == .setup, case .doesNotFit(let window, _, _, let bigger?)? = notice, var placement else { return }
        let area = bigger
        let old = placement.frame
        let centre = CGPoint(x: old.midX, y: old.midY)
        placement.area = area
        placement.frame = AreaGeometry.clamped(
            CGRect(x: centre.x - Double(area.widthPoints) / 2, y: centre.y - Double(area.heightPoints) / 2,
                   width: Double(area.widthPoints), height: Double(area.heightPoints)),
            to: placement.bounds
        )
        self.placement = placement
        self.notice = nil
        followWindows(from: old, thenSnap: window)
        layout()
        recorder.preview.areaChanged()
    }

    func dismissNotice() {
        notice = nil
        layout()
    }

    /// The privacy pane that lets CueCan move other apps' windows. macOS 27 moved Accessibility access into
    /// "Device Control and Data Access". Whether the old settings link still opens that pane is TEST NEEDED.
    static var windowAccessPaneName: String {
        if #available(macOS 27, *) { "Device Control and Data Access" } else { "Accessibility" }
    }

    func openAccessibilitySettings() {
        PrivacyPane.accessibility.open()
        dismissNotice()
    }

    // MARK: - Panels

    private func layout() {
        guard isShowing, let placement else { return }
        let area = placement.frame
        let display = placement.displayFrame
        let visible = placement.visibleFrame
        dragWatcher.area = stage == .starting ? nil : area

        // The dimming, outside the area.
        let strips = AreaGeometry.dimming(around: area, on: display)
        while dimming.count < 4 { dimming.append(.filled(NSColor.black.withAlphaComponent(0.45), level: .captureDimming)) }
        for (index, panel) in dimming.enumerated() {
            if index < strips.count {
                panel.setFrame(strips[index], display: true)
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }

        // The outline, outside the area. While setting up, a band around it moves the area.
        let settingUp = stage == .setup
        let width: CGFloat = switch stage {
        case .setup: hovering == nil ? Self.outlineWidth : 4
        case .starting: Self.outlineWidth
        case .recording: Self.recordingOutlineWidth
        }
        let grab = settingUp ? max(Self.edgeGrab, width) : width
        let lines = [
            CGRect(x: area.minX - width, y: area.maxY, width: area.width + 2 * width, height: width),
            CGRect(x: area.minX - width, y: area.minY - width, width: area.width + 2 * width, height: width),
            CGRect(x: area.minX - width, y: area.minY, width: width, height: area.height),
            CGRect(x: area.maxX, y: area.minY, width: width, height: area.height),
        ]
        let bands = [
            CGRect(x: area.minX - grab, y: area.maxY, width: area.width + 2 * grab, height: grab),
            CGRect(x: area.minX - grab, y: area.minY - grab, width: area.width + 2 * grab, height: grab),
            CGRect(x: area.minX - grab, y: area.minY, width: grab, height: area.height),
            CGRect(x: area.maxX, y: area.minY, width: grab, height: area.height),
        ]
        while edges.count < 4 {
            let panel = OverlayPanel(frame: .zero, level: .captureDimming, passesClicksThrough: false)
            let view = AreaDragView(controller: self, role: .edge)
            panel.contentView = view
            edges.append((panel, view))
        }
        let color: NSColor = stage == .recording ? NSColor.white.withAlphaComponent(0.55) : .controlAccentColor
        for ((panel, view), (line, band)) in zip(edges, zip(lines, bands)) {
            panel.ignoresMouseEvents = !settingUp
            view.isDraggable = settingUp
            view.lineColor = color
            panel.setFrame(band, display: false)
            view.line = line.offsetBy(dx: -band.minX, dy: -band.minY)
            panel.orderFrontRegardless()
        }

        // The corner handles, while setting up.
        let cornerCases = AreaGeometry.Corner.allCases
        while corners.count < cornerCases.count {
            let panel = OverlayPanel(frame: .zero, level: .captureControls, passesClicksThrough: false)
            let view = AreaDragView(controller: self, role: .corner(cornerCases[corners.count]))
            panel.contentView = view
            corners.append((panel, view))
        }
        for ((panel, _), corner) in zip(corners, cornerCases) {
            guard settingUp else {
                panel.orderOut(nil)
                continue
            }
            let point = CGPoint(x: corner.isLeft ? area.minX - width / 2 : area.maxX + width / 2,
                                y: corner.isBottom ? area.minY - width / 2 : area.maxY + width / 2)
            panel.setFrame(CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22), display: true)
            panel.orderFrontRegardless()
        }

        // Where the camera will cover the screen: bright while setting up, fainter once the take runs. A take
        // with no camera has nothing covering it.
        if let zone = recorder.cameraCover, settingUp || recorder.cameraID != nil {
            let frame = CGRect(x: area.minX + zone.rect.minX * area.width, y: area.maxY - zone.rect.maxY * area.height,
                               width: zone.rect.width * area.width, height: zone.rect.height * area.height)
            cover.set(CameraCoverView(corners: zone.corners, scale: area.height, size: frame.size, isQuiet: stage == .recording))
            cover.show(at: frame)
        } else {
            cover.hide()
        }

        // The capsule in its middle, while setting up with nothing dragged over, and above the frame how big
        // text will look, once the area is smaller than the largest that fits (docs/decisions.md, 78).
        if settingUp, hovering == nil {
            let largest = CaptureArea.largest(placement.area.ratio, fittingWidth: placement.bounds.width, height: placement.bounds.height)
            if let title = AreaSize.frameLabel(for: placement.area, largest: largest) {
                let size = label.set(AreaLabelView(title: title))
                label.show(at: outside(size, above: area, in: visible, gap: width + 6))
            } else {
                label.hide()
            }
            let capsuleSize = capsule.set(AreaCapsuleView(controller: self))
            capsule.show(at: centred(capsuleSize, in: area))
        } else {
            label.hide()
            capsule.hide()
        }

        // A window dragged over the area: the tint, "Release to snap", and what it will fill.
        if let hovering, stage != .starting {
            tint.setFrame(area, display: true)
            tint.orderFrontRegardless()
            let size = release.set(ReleaseToSnapView(appName: hovering.appName))
            release.show(at: centred(size, in: area))
            let fillSize = willFill.set(WillFillView(area: placement.windowFrame.size))
            willFill.show(at: outside(fillSize, below: area, in: visible, gap: width + 6))
        } else {
            tint.orderOut(nil)
            release.hide()
            willFill.hide()
        }

        // The notice at the frame.
        if let notice, stage != .starting {
            let size = noticePanel.set(SnapNoticeView(notice: notice, controller: self, canResizeArea: stage == .setup))
            // In the middle of the area, under the capsule when it's there.
            var frame = centred(size, in: area)
            if capsule.isVisible { frame.origin.y = capsule.panel.frame.minY - 10 - size.height }
            frame.origin.x = min(max(visible.minX, frame.origin.x), visible.maxX - size.width)
            frame.origin.y = max(visible.minY, frame.origin.y)
            noticePanel.show(at: frame)
        } else {
            noticePanel.hide()
        }
    }

    private func centred(_ size: CGSize, in area: CGRect) -> CGRect {
        CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Just above the area, or inside its top edge when there's no room above it.
    private func outside(_ size: CGSize, above area: CGRect, in visible: CGRect, gap: CGFloat) -> CGRect {
        let x = min(max(visible.minX, area.midX - size.width / 2), visible.maxX - size.width)
        let y = area.maxY + gap + size.height <= visible.maxY ? area.maxY + gap : area.maxY - gap - size.height
        // An area over the menu bar keeps its label on the desktop, where it can be read.
        return CGRect(x: x, y: min(y, visible.maxY - size.height), width: size.width, height: size.height)
    }

    /// Just below the area, or inside its bottom edge when there's no room below it.
    private func outside(_ size: CGSize, below area: CGRect, in visible: CGRect, gap: CGFloat) -> CGRect {
        let x = min(max(visible.minX, area.midX - size.width / 2), visible.maxX - size.width)
        let y = area.minY - gap - size.height >= visible.minY ? area.minY - gap - size.height : area.minY + gap
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

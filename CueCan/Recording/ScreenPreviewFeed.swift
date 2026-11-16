import AppKit
import Observation
import QuartzCore
import RecorderKit
import SwiftUI

/// The live picture of the area that the setup's and the panel's previews show, from ``AreaPreview``.
///
/// It runs only while a preview is on screen and an area is
/// placed, and only once Screen Recording access has been given, so it never asks for it by itself. Each
/// frame's surface goes straight into the preview layers, without going through SwiftUI.
@Observable
final class ScreenPreviewFeed {
    @ObservationIgnored private unowned let recorder: RecorderModel
    @ObservationIgnored private var stream: AreaPreview?
    /// What the stream shows, as confirmed: a failed update leaves it as it was, so it's retried.
    @ObservationIgnored private var reconciler = PreviewReconciler()
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private let layers = NSHashTable<CALayer>.weakObjects()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var demand = PreviewDemandQueue()
    @ObservationIgnored private var streamID: UUID?
    @ObservationIgnored private var latest: IOSurfaceBox?

    /// Whether a frame has arrived since the preview started.
    private(set) var hasPicture = false
    /// Screen Recording access hasn't been given, so there's no live picture.
    private(set) var needsPermission = false

    init(recorder: RecorderModel) {
        self.recorder = recorder
    }

    /// A preview came on screen.
    func viewerAppeared() {
        viewers += 1
        areaChanged()
    }

    func viewerDisappeared() {
        viewers = max(0, viewers - 1)
        areaChanged()
    }

    func attach(_ layer: CALayer) {
        layers.add(layer)
        if let latest { layer.contents = latest.surface }
    }

    /// Starts, moves or stops the stream to match the area and whether anything shows it.
    func areaChanged() {
        let wanted: PreviewTarget? = {
            guard viewers > 0, let placement = recorder.area.placement, recorder.phase != .idle else { return nil }
            return PreviewTarget(displayID: placement.displayID,
                                 sourceRect: AreaGeometry.sourceRect(for: placement.frame, onDisplay: placement.displayFrame))
        }()
        needsPermission = wanted != nil && !ScreenCapture.hasPermission
        guard let first = demand.request(wanted) else { return }
        task = Task { [weak self] in
            guard let self else { return }
            var request: PreviewDemandQueue.Request? = first
            while let current = request {
                await self.apply(current.target)
                request = self.demand.completed(current)
            }
            self.task = nil
        }
    }

    private func apply(_ wanted: PreviewTarget?) async {
        let wanted = ScreenCapture.hasPermission ? wanted : nil
        switch reconciler.step(toward: wanted) {
        case .none:
            return
        case .stop:
            await stopStream()
        case .update(let target):
            do {
                try await stream?.update(area: target.sourceRect)
                reconciler.didApply(target)
            } catch {
                // The stream keeps its old crop. Nothing is recorded as applied, so the next change retries.
            }
        case .start(let target):
            await stopStream()
            do {
                let stream = try await AreaPreview.start(displayID: target.displayID, area: target.sourceRect)
                let id = UUID()
                stream.onFrame { [weak self] surface in
                    let box = IOSurfaceBox(surface: surface)
                    DispatchQueue.main.async { self?.show(box, from: id) }
                }
                self.stream = stream
                streamID = id
                reconciler.didApply(target)
            } catch {
                needsPermission = !ScreenCapture.hasPermission
            }
        }
    }

    private func stopStream() async {
        guard let stream else { return }
        self.stream = nil
        streamID = nil
        reconciler.didApply(nil)
        latest = nil
        hasPicture = false
        for layer in layers.allObjects { layer.contents = nil }
        await stream.stop()
    }

    private func show(_ box: IOSurfaceBox, from id: UUID) {
        guard streamID == id else { return }
        latest = box
        if !hasPicture { hasPicture = true }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.allObjects { layer.contents = box.surface }
        CATransaction.commit()
    }

    /// Frames delivered by the current stream, for measuring what the preview costs.
    var framesDelivered: Int { stream?.framesDelivered ?? 0 }
}

/// A frame's surface, handed from the capture queue to the main thread.
nonisolated private struct IOSurfaceBox: @unchecked Sendable {
    let surface: IOSurfaceRef
}

/// The live screen picture, stretched to its frame: the export preview places and crops it.
struct ScreenPreviewView: NSViewRepresentable {
    let feed: ScreenPreviewFeed

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = CALayer()
        layer.contentsGravity = .resize
        layer.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        // A layer-hosting view: the layer is set before the view wants one.
        view.layer = layer
        view.wantsLayer = true
        feed.attach(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

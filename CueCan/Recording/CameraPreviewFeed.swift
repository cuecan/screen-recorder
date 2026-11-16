import AppKit
import AVFoundation
import RecorderKit

/// Live camera images, replayed to new views without modifying the camera's capture graph.
@MainActor
final class CameraPreviewFeed {
    private let delivery = CameraPreviewDelivery()
    private let views = NSHashTable<CameraPreview.PreviewView>.weakObjects()
    private var latest: CameraPreviewFrame?

    init(camera: CameraCapture) {
        let delivery = delivery
        camera.onPreviewFrame { [weak self] frame in
            guard delivery.submit(frame) else { return }
            DispatchQueue.main.async { self?.deliver() }
        }
    }

    func attach(_ view: CameraPreview.PreviewView) {
        views.add(view)
        if let latest { view.show(latest) }
    }

    func detach(_ view: CameraPreview.PreviewView) { views.remove(view) }

    private func deliver() {
        guard let update = delivery.take() else { return }
        latest = update.frame
        for view in views.allObjects {
            if let frame = update.frame { view.show(frame) } else { view.clear() }
        }
    }
}

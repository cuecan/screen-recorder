import AVFoundation
import AppKit
import RecorderKit
import SwiftUI

/// The camera's recorded pixels in a display layer. New views, crops and layouts never add or remove
/// capture connections, so opening a preview cannot interrupt the camera's recording.
struct CameraPreview: NSViewRepresentable {
    let feed: CameraPreviewFeed
    /// Fractions of the recorded image, from its top left. Nil uses aspect fill.
    var crop: CGRect?
    var mirroringChanged: (@MainActor (Bool) -> Void)?

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.crop = crop
        view.connect(to: feed)
        let changed = mirroringChanged
        Task { @MainActor in changed?(false) }
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.connect(to: feed)
        if view.crop != crop { view.crop = crop }
    }

    static func dismantleNSView(_ view: PreviewView, coordinator: ()) { view.disconnect() }

    final class PreviewView: NSView {
        let pictureLayer = AVSampleBufferDisplayLayer()
        var crop: CGRect? { didSet { needsLayout = true } }
        private weak var feed: CameraPreviewFeed?
        private let renderer: any CameraSampleRenderer

        override init(frame: NSRect) {
            if #available(macOS 27, *) { renderer = ImmediateCameraSampleRenderer(layer: pictureLayer) }
            else { renderer = QueuedCameraSampleRenderer(layer: pictureLayer) }
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
            layer?.masksToBounds = true
            layer?.addSublayer(pictureLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func connect(to feed: CameraPreviewFeed) {
            guard self.feed !== feed else { return }
            self.feed?.detach(self)
            self.feed = feed
            feed.attach(self)
        }

        func disconnect() { feed?.detach(self); feed = nil; renderer.clear() }
        func show(_ frame: CameraPreviewFrame) { renderer.show(frame) }
        func clear() { renderer.clear() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let crop, crop.width > 0, crop.height > 0 {
                pictureLayer.videoGravity = .resize
                let width = bounds.width / crop.width, height = bounds.height / crop.height
                pictureLayer.frame = CGRect(x: -crop.minX * width, y: -(1 - crop.maxY) * height, width: width, height: height)
            } else {
                pictureLayer.videoGravity = .resizeAspectFill
                pictureLayer.frame = bounds
            }
            CATransaction.commit()
        }
    }
}

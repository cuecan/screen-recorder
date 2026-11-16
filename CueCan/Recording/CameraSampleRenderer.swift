import AVFoundation
import RecorderKit

/// A display renderer owns no capture connection. Its pixel buffers are the recorder's existing images.
@MainActor
protocol CameraSampleRenderer: AnyObject {
    func show(_ frame: CameraPreviewFrame)
    func clear()
}

@available(macOS 27, *)
@MainActor
final class ImmediateCameraSampleRenderer: CameraSampleRenderer {
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let receiver: AVSampleBufferVideoRenderer.Receiver
    private var clearing = false
    private var pending: CameraPreviewFrame?

    init(layer: AVSampleBufferDisplayLayer) {
        receiver = synchronizer.sampleBufferReceiver(adding: layer.sampleBufferRenderer)
    }

    func show(_ frame: CameraPreviewFrame) {
        guard !clearing else { pending = frame; return }
        guard let sample = frame.makeDisplaySample() else { return }
        let result = receiver.enqueueImmediately(CMReadySampleBuffer(unsafeBuffer: sample))
        switch result {
        case .enqueued, .enqueuedWithDecodeFailures: pending = nil
        case .cancelledDueToFlush: pending = frame
        case .cancelledDueToFlushRequiredToResume, .cancelledDueToError:
            receiver.flush()
        @unknown default:
            receiver.flush()
        }
    }

    func clear() {
        pending = nil
        guard !clearing else { return }
        clearing = true
        Task { [weak self] in
            guard let self else { return }
            await self.receiver.flush(removingDisplayedImage: true)
            self.clearing = false
            if let pending = self.pending { self.pending = nil; self.show(pending) }
        }
    }
}

@available(macOS, introduced: 14, obsoleted: 27)
@MainActor
final class QueuedCameraSampleRenderer: CameraSampleRenderer {
    private let renderer: AVSampleBufferVideoRenderer
    init(layer: AVSampleBufferDisplayLayer) { renderer = layer.sampleBufferRenderer }
    func show(_ frame: CameraPreviewFrame) {
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData, let sample = frame.makeDisplaySample() else { return }
        renderer.enqueue(sample)
    }
    func clear() { renderer.flush(removingDisplayedImage: true) }
}

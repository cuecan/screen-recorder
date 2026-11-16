import AppKit
import Foundation
import RenderKit

/// Coalesces still reads while auditioning a framing gesture. The player receives instructions
/// immediately; this supplies a poster when paused before capture delivered its opening pictures.
@MainActor
final class FramingAudition {
    private var latest: (built: BuiltComposition, time: Double, receive: (NSImage) -> Void)?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func show(_ built: BuiltComposition, at time: Double, receive: @escaping (NSImage) -> Void) {
        latest = (built, time, receive)
        guard task == nil else { return }
        let generation = generation
        task = Task { [weak self] in
            while let self, self.generation == generation, let request = self.latest {
                self.latest = nil
                if let independent = try? request.built.copyForReading() {
                    let time = request.time
                    let read = Task.detached { try await FrameGrabber.stills(of: independent, at: [time], maximumWidth: 2600).first }
                    let still = try? await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
                    guard !Task.isCancelled, self.generation == generation else { return }
                    // Published even when a newer target is already queued: reads run one at a time, so
                    // this still is newer than the one on screen. Dropping it would freeze the opening
                    // poster for as long as a drag outpaces the decoder.
                    if let still, let image = NSImage(data: still.jpeg) { request.receive(image) }
                }
                do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
            }
            if let self, self.generation == generation { self.task = nil }
        }
    }

    func cancel() {
        generation = UUID()
        latest = nil
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

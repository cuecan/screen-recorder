import Foundation

/// One cancellable mastering worker and one cached mix, scoped to an editor. A superseding request
/// waits for cancelled work to finish before allocating another mix.
public actor LoudnessPreviewRenderer {
    private var latest = UUID()
    private var worker: (id: UUID, task: Task<PreviewAudioFile?, any Error>)?
    private var cache: (key: Data, file: PreviewAudioFile?)?

    public init() {}

    /// `key` identifies the captured edit, resolved media and mastering settings, rather than its picture size.
    public func audio(for key: Data, of built: BuiltComposition, using mastering: @escaping Exporter.Mastering) async throws -> PreviewAudioFile? {
        let request = UUID()
        latest = request
        if let worker {
            worker.task.cancel()
            _ = await worker.task.result
        }
        try Task.checkCancellation()
        guard latest == request else { throw CancellationError() }
        if let cache, cache.key == key { return cache.file }
        let task = Task.detached(priority: .userInitiated) { () throws -> PreviewAudioFile? in
            let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-normalized-preview-\(UUID()).wav")
            do {
                guard try await MasteredSound.writeMix(of: built, to: url, using: mastering) else { return nil }
                try Task.checkCancellation()
                return PreviewAudioFile(url: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
        worker = (request, task)
        defer { if worker?.id == request { worker = nil } }
        let file = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard latest == request else { throw CancellationError() }
        cache = (key, file)
        return file
    }

    /// Invalidates pending results and releases the cache. A player holding a file keeps its own lease.
    public func clear() {
        latest = UUID()
        worker?.task.cancel()
        cache = nil
    }
}

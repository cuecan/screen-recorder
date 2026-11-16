import AppKit
import ProjectKit
import RenderKit

/// The takes' thumbnails in the sidebar (docs/ui.md, P1 and P2; docs/decisions.md, 63): each edit's first
/// picture in its look (61), in the shape its editor shows (77): the video for Landscape, the Short for
/// Vertical, and for a take made for both whichever the toggle under the preview is on.
///
/// One is drawn per edit revision and shape, one take at a time, and kept in the caches folder, so the list draws
/// them once rather than every time it reloads.
@MainActor @Observable
final class TakeThumbnails {
    /// The thumbnail's size in the sidebar, in points.
    nonisolated static let size = CGSize(width: 236, height: 133)

    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var queue = ThumbnailQueue()
    @ObservationIgnored private var summaries: [URL: ProjectSummary] = [:]

    func request(_ summary: ProjectSummary) {
        summaries[summary.url] = summary
        queue.request(summary.url, revision: summary.thumbnailVersion)
        drawNext()
    }

    func forget(_ url: URL) {
        images[url] = nil
        summaries[url] = nil
        queue.forget(url)
    }

    #if DEBUG
    /// For Xcode's previews, which snapshot before anything is drawn: the cached thumbnails, read now, and the
    /// rest asked for.
    func loadCachedForPreview(_ takes: [ProjectSummary]) {
        for take in takes where !queue.hasCompleted(take.url, revision: take.thumbnailVersion) {
            if let data = try? Data(contentsOf: Self.cacheURL(for: take)), let image = NSImage(data: data) {
                images[take.url] = image
            } else {
                request(take)
            }
        }
    }
    #endif

    nonisolated private static let cacheFolder = URL.cachesDirectory.appending(path: "CueCan/Thumbnails", directoryHint: .isDirectory)

    nonisolated private static func cacheURL(for summary: ProjectSummary) -> URL {
        cacheFolder.appending(path: "\(summary.id.uuidString)-r\(summary.editRevision)-\(summary.shape.rawValue).jpg")
    }

    private func drawNext() {
        guard let request = queue.startNext(), let summary = summaries[request.project] else { return }
        Task {
            let data = await Task.detached(priority: .utility) { await Self.thumbnail(for: summary) }.value
            if queue.finish(request) { images[summary.url] = data.flatMap(NSImage.init(data:)) }
            drawNext()
        }
    }

    /// The thumbnail as JPEG data, from the cache or drawn now. Nil when there's no picture, such as an
    /// edit with everything cut.
    nonisolated private static func thumbnail(for summary: ProjectSummary) async -> Data? {
        let folder = cacheFolder
        let cached = cacheURL(for: summary)
        if let data = try? Data(contentsOf: cached) { return data }
        guard let project = try? ProjectFolder(opening: summary.url), let inputs = try? RenderInputs.load(project), inputs.edit.revision == summary.editRevision else { return nil }
        let output = summary.shape
        // Twice the size it's shown at, for a Retina display.
        let width = Int((output == .vertical ? size.height * 9 / 16 : size.width) * 2)
        guard let built = try? await CompositionBuilder.build(inputs, output: output, scale: 0.5),
            let still = try? await FrameGrabber.stills(of: built, at: [0], maximumWidth: width).first
        else { return nil }
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Only the latest revision's is kept.
        let older = (try? manager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in older where name.hasPrefix(summary.id.uuidString) { try? manager.removeItem(at: folder.appending(path: name)) }
        try? still.jpeg.write(to: cached, options: .atomic)
        return still.jpeg
    }
}

extension ProjectSummary {
    /// What a thumbnail is a picture of: the edit's revision and the shape shown. It changes when either does.
    var thumbnailVersion: Int { editRevision * 2 + (shape == .vertical ? 1 : 0) }
}

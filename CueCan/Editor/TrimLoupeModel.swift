import AppKit
import Observation
import ProjectKit
import RenderKit

/// One decoder and the newest waiting target, with a twelve-pair LRU cache scoped to a gesture.
/// Cancelling hides the loupe immediately; an old decoder cannot replace a new gesture's images.
@Observable
final class TrimLoupeModel {
    typealias Producer = @Sendable (TrimPreviewPlan) async throws -> TrimPreviewFrames
    struct Picture {
        let image: NSImage
        let time: TimeInterval
        init?(_ still: Still?) {
            guard let still, let image = NSImage(data: still.jpeg) else { return nil }
            self.image = image
            time = still.time
        }
    }
    struct Pair {
        let outgoing: Picture?
        let incoming: Picture?
        init(_ frames: TrimPreviewFrames) {
            outgoing = Picture(frames.outgoing)
            incoming = Picture(frames.incoming)
        }
    }
    /// Presentation is mutually exclusive: stale pictures may cover a loading or failed target,
    /// but a hidden loupe never owns visible feedback.
    enum State {
        case hidden
        case loading(TrimPreviewPlan, previous: Pair?)
        case ready(TrimPreviewPlan, Pair)
        case failed(TrimPreviewPlan, previous: Pair?, problem: String)
    }
    private(set) var state = State.hidden
    var visible: Bool { if case .hidden = state { false } else { true } }
    var plan: TrimPreviewPlan? {
        switch state {
        case .hidden: nil
        case .loading(let plan, _), .ready(let plan, _), .failed(let plan, _, _): plan
        }
    }
    var pictures: Pair? {
        switch state {
        case .hidden: nil
        case .loading(_, let previous), .failed(_, let previous, _): previous
        case .ready(_, let pair): pair
        }
    }
    var updating: Bool { if case .loading = state { true } else { false } }
    var problem: String? { if case .failed(_, _, let message) = state { message } else { nil } }
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var base: TrimLoupeRequest.Key?
    @ObservationIgnored private var target: TrimLoupeRequest.Key?
    @ObservationIgnored private var pending: (TrimLoupeRequest, TrimPreviewPlan, ProjectFolder, UUID)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var briefly = false
    @ObservationIgnored private var session: TrimPreviewSession?
    @ObservationIgnored private var cache: [(TrimLoupeRequest.Key, Pair)] = []
    @ObservationIgnored private let producer: Producer?

    init(producer: Producer? = nil) { self.producer = producer }

    func show(_ request: TrimLoupeRequest, folder: ProjectFolder, briefly: Bool = false) {
        if base != request.base { end(); base = request.base }
        expiry?.cancel()
        self.briefly = briefly
        // A cold decoder must not consume the whole keyboard feedback interval before pictures arrive.
        if briefly { dismiss(after: .seconds(12)) }
        guard let plan = try? request.plan() else { end(); return }
        guard target != request.key else {
            if briefly, !updating { dismiss(after: .milliseconds(1500)) }
            return
        }
        target = request.key
        if let index = cache.firstIndex(where: { $0.0 == request.key }) {
            let hit = cache.remove(at: index)
            cache.append(hit)
            state = .ready(plan, hit.1)
            pending = nil
            if briefly { dismiss(after: .milliseconds(1500)) }
        } else {
            state = .loading(plan, previous: pictures)
            pending = (request, plan, folder, generation)
            start()
        }
    }

    func end() {
        generation = UUID()
        expiry?.cancel()
        expiry = nil
        briefly = false
        worker?.cancel()
        pending = nil
        target = nil
        base = nil
        session = nil
        cache.removeAll()
        state = .hidden
    }

    private func start() {
        guard worker == nil, pending != nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            defer { worker = nil; start() }
            while !Task.isCancelled, let (request, plan, folder, token) = pending {
                pending = nil
                do {
                    let frames: TrimPreviewFrames
                    if let producer { frames = try await producer(plan) }
                    else {
                        let reader: TrimPreviewSession
                        if let session { reader = session }
                        else {
                            reader = try await Task.detached(priority: .userInitiated) { try TrimPreviewSession(folder: folder) }.value
                            try Task.checkCancellation()
                            guard token == generation else { continue }
                            session = reader
                        }
                        frames = try await reader.frames(for: plan)
                    }
                    try Task.checkCancellation()
                    guard token == generation else { continue }
                    let pair = Pair(frames)
                    cache.removeAll { $0.0 == request.key }
                    cache.append((request.key, pair))
                    if cache.count > 12 { cache.removeFirst(cache.count - 12) }
                    if target == request.key {
                        state = .ready(plan, pair)
                        if briefly { dismiss(after: .milliseconds(1500)) }
                    }
                } catch {
                    if Task.isCancelled { break }
                    if token == generation, target == request.key {
                        state = .failed(plan, previous: pictures, problem: error.localizedDescription)
                        if briefly { dismiss(after: .milliseconds(1500)) }
                    }
                }
                do { try await Task.sleep(for: .milliseconds(60)) } catch { break }
            }
        }
    }

    private func dismiss(after delay: Duration) {
        expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.end()
        }
    }
}

/// Tracks offline rendering as progressing, retrying, or finished. A framework that repeatedly returns
/// no frames must fail rather than spin forever. The retry limit is a guard, not an audio-quality setting:
/// with ``retryDelay`` between tries, the default gives up after about 0.6 s with no audio.
struct OfflineRenderProgress {
    /// How long to wait before trying again after a render that produced nothing.
    static let retryDelay = Duration.milliseconds(10)

    enum State: Equatable {
        case rendering(frames: Int)
        case retrying(frames: Int, attempts: Int)
        case finished
    }

    let totalFrames: Int
    let maximumRetries: Int
    /// What's rendering, for the error, such as "AUSoundIsolation".
    let renderer: String
    private(set) var state: State

    init(totalFrames: Int, renderer: String, maximumRetries: Int = 64) {
        self.totalFrames = totalFrames
        self.renderer = renderer
        self.maximumRetries = maximumRetries
        state = totalFrames > 0 ? .rendering(frames: 0) : .finished
    }

    var isFinished: Bool { state == .finished }

    mutating func advance(by count: Int) throws {
        let frames: Int
        let retries: Int
        switch state {
        case .rendering(let produced): (frames, retries) = (produced, 0)
        case .retrying(let produced, let attempts): (frames, retries) = (produced, attempts)
        case .finished: return
        }
        if count > 0 {
            state = frames + count >= totalFrames ? .finished : .rendering(frames: frames + count)
        } else {
            guard retries < maximumRetries else {
                throw AudioKitError.modelFailed(renderer, "Offline rendering stopped producing audio. Try again.")
            }
            state = .retrying(frames: frames, attempts: retries + 1)
        }
    }
}

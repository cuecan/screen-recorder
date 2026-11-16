import CoreMedia
import Foundation
import ProjectKit

/// One recording: every source to its own file in the project's `recordings/`, placed on one clock.
///
/// The captures keep running for the widget's previews before and after; the session only taps their
/// buffers between ``start()`` and ``stop()``. Nothing is processed while recording (docs/decisions.md, 17).
public final class RecordingSession: @unchecked Sendable {
    public struct Sources: Sendable {
        public var screen: ScreenCapture?
        public var camera: CameraCapture?
        public var mic: MicCapture?
        public var captureArea: CaptureArea?

        public init(screen: ScreenCapture? = nil, camera: CameraCapture? = nil, mic: MicCapture? = nil, captureArea: CaptureArea? = nil) {
            self.screen = screen
            self.camera = camera
            self.mic = mic
            self.captureArea = captureArea
        }
    }

    /// A take's name, such as "Screen recording 10:42", or "Camera recording 10:42" with no screen
    /// (docs/ui.md, R9).
    public static func title(recordsScreen: Bool, at date: Date) -> String {
        "\(recordsScreen ? "Screen recording" : "Camera recording") \(date.formatted(date: .omitted, time: .shortened))"
    }

    public let clock = RecordingClock()
    public let name: String
    private let sources: Sources
    /// How far the camera runs behind the mic, as measured for this pair: the take is cut with the camera
    /// placed by it (``TakeSpan``).
    private let lipSync: TimeInterval
    /// The take's folder, relative to the project, such as `recordings/2026-11-06 10.42.15`.
    private let relativeFolder: String
    private let folderURL: URL

    private let screenWriter: TrackWriter?
    private let systemWriter: TrackWriter?
    private let cameraWriter: TrackWriter?
    private let micWriter: WAVStreamWriter?
    private let lock = NSLock()
    /// Display sleep stops ScreenCaptureKit's streams. Keep them alive for the take, including Pause,
    /// then release the assertion after finalization or discard. This does not prevent a manual lock.
    private var recordingActivity: (any NSObjectProtocol)?
    var keepsCaptureAwake: Bool { lock.withLock { recordingActivity != nil } }

    private func releaseRecordingActivity() {
        let activity = lock.withLock {
            let activity = recordingActivity
            recordingActivity = nil
            return activity
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
    private enum State {
        case prepared, recording, paused
        case failed(TrackFailure)
        case finishing(Task<RecordedSource, Error>, failure: TrackFailure?)
        case finished(Result<RecordedSource, Error>, failure: TrackFailure?)
        case discarded

        var failure: TrackFailure? {
            switch self {
            case .failed(let failure): failure
            case .finishing(_, let failure), .finished(_, let failure): failure
            default: nil
            }
        }
    }
    private var state = State.prepared
    private var micPlacement = SamplePlacement(sampleRate: MicCapture.sampleRate)
    private var micLostAt: TimeInterval?
    private var micFailure: (any Error)?
    private var failureHandler: (@Sendable (TrackFailure) -> Void)?
    /// The first failure, retained while finalizing and after Stop so the app can report it reliably.
    public var trackFailure: TrackFailure? { lock.withLock { state.failure } }

    /// The encoded tracks, in the same order for callbacks, finalization and diagnostics.
    private var encodedTracks: [(kind: SourceTrack.Kind, writer: TrackWriter)] {
        [(SourceTrack.Kind.screen, screenWriter), (.camera, cameraWriter), (.systemAudio, systemWriter)]
            .compactMap { kind, writer in writer.map { (kind, $0) } }
    }

    public init(project: ProjectFolder, sources: Sources, lipSync: TimeInterval = 0, startedAt date: Date = .now) throws {
        self.lipSync = lipSync
        let stamp = date.formatted(Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)", timeZone: .current, calendar: .current))
        name = Self.title(recordsScreen: sources.screen != nil, at: date)
        relativeFolder = "\(ProjectFolder.Folder.recordings.rawValue)/\(stamp)"
        let take = project.url.appending(path: relativeFolder, directoryHint: .isDirectory)
        folderURL = take
        try FileManager.default.createDirectory(at: take, withIntermediateDirectories: true)
        self.sources = sources

        screenWriter = sources.screen.map { _ in TrackWriter(url: take.appending(path: "screen.mov"), kind: .video(frameRate: ScreenCapture.frameRate)) }
        systemWriter = sources.screen.flatMap { $0.capturesSystemAudio ? TrackWriter(url: take.appending(path: "system.m4a"), kind: .aac) : nil }
        cameraWriter = sources.camera.map { TrackWriter(url: take.appending(path: "camera.mov"), kind: .video(frameRate: $0.frameRate)) }
        micWriter = try sources.mic.map { _ in try WAVStreamWriter(url: take.appending(path: "mic.wav"), sampleRate: MicCapture.sampleRate) }
    }

    /// Calls `handler` once, from any thread, when the first track stops recording during the take, so the
    /// take can stop there. Set it before ``start()``.
    public func onTrackFailure(_ handler: @escaping @Sendable (TrackFailure) -> Void) {
        lock.withLock { failureHandler = handler }
    }

    /// Reports a track that stopped recording: a capture that stopped by itself, a device that went away, or
    /// a camera gone quiet. Only the first failure is reported, and none once the take is stopping.
    public func trackFailed(_ kind: SourceTrack.Kind, reason: String) {
        let report: (TrackFailure, (@Sendable (TrackFailure) -> Void)?)? = lock.withLock {
            switch state {
            case .recording, .paused: break
            default: return nil
            }
            // Stop accepting new buffers now. The UI may be busy and finalize the files later.
            clock.pause()
            let failure = TrackFailure(kind: kind, at: clock.elapsed, reason: reason)
            state = .failed(failure)
            return (failure, failureHandler)
        }
        if let (failure, handler) = report { handler?(failure) }
    }

    /// Whether the camera is being recorded and has sent no frame for `threshold` seconds of recording.
    public func cameraHasStalled(threshold: TimeInterval) -> Bool {
        guard let cameraWriter, lock.withLock({ if case .recording = state { true } else { false } }) else { return false }
        return TrackFailure.isStalled(lastFrame: cameraWriter.lastWrittenTime, elapsed: clock.elapsed, threshold: threshold)
    }

    /// Starts writing every source from now.
    public func start() {
        lock.lock()
        guard case .prepared = state else { lock.unlock(); return }
        state = .recording
        recordingActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled], reason: "Recording video in CueCan")
        defer { lock.unlock() }
        let clock = clock
        clock.start()
        for (kind, writer) in encodedTracks {
            writer.onFailure { [weak self] error in self?.trackFailed(kind, reason: error.localizedDescription) }
        }
        if let screenWriter {
            sources.screen?.videoSink.set { buffer, host in
                if let time = clock.place(host) { screenWriter.append(buffer, at: time) }
            }
        }
        if let systemWriter {
            sources.screen?.audioSink.set { buffer, host in
                if let time = clock.place(host) { systemWriter.append(buffer, at: time) }
            }
        }
        if let cameraWriter {
            sources.camera?.sink.set { buffer, host in
                if let time = clock.place(host) { cameraWriter.append(buffer, at: time) }
            }
        }
        if let micWriter {
            sources.mic?.sink.set { [weak self] buffer, host in
                guard let self, let time = clock.place(host) else { return }
                let samples = MicCapture.floats(in: buffer)
                // Each buffer lands where its time says, so a gap stays a gap and the mic keeps time
                // with the picture.
                let (silence, skip) = self.lock.withLock { self.micPlacement.place(count: samples.count, at: time) }
                do {
                    if silence > 0 { try micWriter.append([Float](repeating: 0, count: silence)) }
                    if skip < samples.count { try micWriter.append(Array(samples[skip...])) }
                } catch {
                    self.lock.withLock { self.micFailure = error }
                    self.trackFailed(.microphone, reason: error.localizedDescription)
                }
            }
        }
    }

    public func pause() {
        lock.withLock {
            guard case .recording = state else { return }
            clock.pause()
            state = .paused
        }
    }
    public func resume() {
        lock.withLock {
            guard case .paused = state else { return }
            clock.resume()
            state = .recording
        }
    }

    /// Notes that the mic disappeared, so the gap is marked rather than hidden.
    public func micWasLost() {
        let elapsed = clock.elapsed
        lock.withLock { if micLostAt == nil { micLostAt = elapsed } }
    }

    /// Stops writing and closes every file without keeping any of it, for a discarded take
    /// (docs/decisions.md, 51). The take's files are deleted with its project by
    /// ``DiscardedTake/delete(_:in:)``.
    public func discard() {
        let canDiscard = lock.withLock {
            switch state {
            case .prepared, .recording, .paused, .failed: state = .discarded; return true
            default: return false
            }
        }
        guard canDiscard else { return }
        defer { releaseRecordingActivity() }
        sources.screen?.videoSink.set(nil)
        sources.screen?.audioSink.set(nil)
        sources.camera?.sink.set(nil)
        sources.mic?.sink.set(nil)
        for (_, writer) in encodedTracks { writer.cancel() }
        try? micWriter?.finish()
    }

    /// The take's folder inside the project.
    public var takeFolder: URL { folderURL }

    /// Stops writing, closes every file and returns the tracks, each with its offset on the shared clock.
    public func stop() async throws -> RecordedSource {
        let task: Task<RecordedSource, Error> = lock.withLock {
            switch state {
            case .finishing(let task, _): return task
            case .finished(let result, _): return Task { try result.get() }
            case .discarded: return Task { throw CancellationError() }
            case .prepared, .recording, .paused, .failed:
                let failure = state.failure
                clock.pause()
                let task = Task { try await self.finalize() }
                state = .finishing(task, failure: failure)
                return task
            }
        }
        let result = await task.result
        lock.withLock { state = .finished(result, failure: state.failure) }
        return try result.get()
    }

    private func finalize() async throws -> RecordedSource {
        defer { releaseRecordingActivity() }
        let stopTime = clock.elapsed
        sources.screen?.videoSink.set(nil)
        sources.screen?.audioSink.set(nil)
        sources.camera?.sink.set(nil)
        sources.mic?.sink.set(nil)

        var pending: [RecordingFinalizer.Track] = []
        for (kind, writer) in encodedTracks {
            pending.append(.init(kind: kind, url: writer.url) {
                try await writer.finish(holdingLastFrameUntil: kind == .screen ? stopTime : nil) ? writer.firstTime : nil
            })
        }
        if let micWriter {
            pending.append(.init(kind: .microphone, url: micWriter.url) {
                try micWriter.finish()
                let (first, failure) = self.lock.withLock { (self.micPlacement.start, self.micFailure) }
                // The WAV is written as it goes, so what it holds before a failure is kept.
                if let failure, micWriter.duration == 0 { throw RecorderError.couldNotWrite(micWriter.url, failure.localizedDescription) }
                return micWriter.duration > 0 ? first : nil
            })
        }
        let (written, failed) = await RecordingFinalizer.finish(pending)
        var dropped: [SourceTrack.Kind: Int] = [:]
        for (kind, writer) in encodedTracks {
            if writer.dropped > 0 { dropped[kind] = writer.dropped }
        }
        let lostAt = lock.withLock { micLostAt }

        // The rate each video writer was set up for, which the edit's frame clock follows.
        var captureRates: [SourceTrack.Kind: Int] = [:]
        for (kind, writer) in encodedTracks {
            if case .video(let rate) = writer.kind { captureRates[kind] = rate }
        }
        // A writer that failed leaves the movie fragments it wrote before it failed (docs/decisions.md, 15).
        // They're kept when they read; otherwise the take goes on without that track.
        let firstTimes: [SourceTrack.Kind: TimeInterval?] = [.screen: screenWriter?.firstTime, .camera: cameraWriter?.firstTime,
            .systemAudio: systemWriter?.firstTime, .microphone: lock.withLock { micPlacement.start }]
        let rates = captureRates
        let recovered = await RecordingFinalizer.recover(written: written, failed: failed, firstTimes: firstTimes) { kind, url in
            try await MediaProbe.probe(url, captureRate: rates[kind])
        }
        // Every track is cut to the time they all cover, so the take starts and ends with every picture and
        // the voice in place (docs/decisions.md, 87).
        let folder = relativeFolder
        let placed = try await RecordingFinalizer.place(recovered.tracks, lipSync: lipSync,
            file: { .inProject("\(folder)/\($0.url.lastPathComponent)") },
            trim: { try await TrackTrimmer.trim($0) },
            probe: { kind, url in try await MediaProbe.probe(url, captureRate: rates[kind]) })
        guard let placed else {
            if !recovered.lost.isEmpty { throw RecorderError.finalizationFailed(recovered.lost.map { "\($0.url.lastPathComponent): \($0.message)" }) }
            throw RecorderError.nothingRecorded
        }
        var recorded = RecordedSource(name: name, tracks: placed.tracks, captureArea: sources.captureArea, droppedBuffers: dropped, micLostAt: lostAt)
        recorded.clockOffset = placed.origin
        recorded.lipSync = placed.lipSync
        recorded.lostTracks = recovered.lost.map(\.kind)
        recorded.outOfOrderBuffers = encodedTracks
            .reduce(into: [:]) { counts, pair in if pair.writer.outOfOrder > 0 { counts[pair.kind] = pair.writer.outOfOrder } }
        return recorded
    }
}

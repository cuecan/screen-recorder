import AVFoundation
import CoreMedia
import Foundation
import OSLog

/// One track's file: an `AVAssetWriter` of its own, so a stalled camera never holds up the screen, writing
/// fragmented movie files so a crash or a full disk loses seconds, not the recording (docs/decisions.md, 15).
///
/// Video is HEVC from the hardware encoder. System audio is AAC, mono. Buffers arrive
/// already placed on the recording's clock.
///
/// Buffers reach the encoder in order and, for video, at least half a frame apart. A video frame at the same
/// time as the one before, or earlier, makes the movie writer fail for good a frame or two later (AVFoundation
/// −11800 over CoreMedia −16364: it ended a real screen recording, and reproduces with
/// `AVAssetWriter` alone). Such a buffer is dropped and counted instead. A failure is reported once, as it
/// happens, through ``onFailure(_:)``, so the take can stop there.
public final class TrackWriter: @unchecked Sendable {
    public enum Kind: Sendable {
        case video(frameRate: Int)
        case aac
    }

    public let url: URL
    public let kind: Kind
    private let lock = NSLock()
    /// The lock protects both the lifecycle and its resource bundle.
    private enum State {
        case waiting
        case writing(Active)
        case failed(Active?, any Error)
        case finishing(Task<Bool, Error>)
        case finished(Result<Bool, Error>)
        case cancelled
    }
    private final class Active: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        var lastTime: TimeInterval
        init(writer: AVAssetWriter, input: AVAssetWriterInput, time: TimeInterval) {
            self.writer = writer
            self.input = input
            lastTime = time
        }
    }
    private var state = State.waiting
    private var first: TimeInterval?
    private var last: TimeInterval?
    private var droppedCount = 0
    private var outOfOrderCount = 0
    private var failureHandler: (@Sendable (any Error) -> Void)?
    private static let log = Logger(subsystem: "com.jelled.CueCan", category: "recording")
    /// Where the first buffer landed on the recording's clock.
    public var firstTime: TimeInterval? { lock.withLock { first } }
    /// Where the latest buffer written landed on the recording's clock.
    public var lastWrittenTime: TimeInterval? { lock.withLock { last } }
    /// Buffers dropped because the encoder was busy.
    public var dropped: Int { lock.withLock { droppedCount } }
    /// Buffers dropped because they didn't move time on from the one before.
    public var outOfOrder: Int { lock.withLock { outOfOrderCount } }

    public init(url: URL, kind: Kind) {
        self.url = url
        self.kind = kind
    }

    /// Calls `handler` once, on the capture's queue, when the file stops taking buffers.
    public func onFailure(_ handler: @escaping @Sendable (any Error) -> Void) {
        lock.withLock { failureHandler = handler }
    }

    /// Whether a buffer at `time` moves time on far enough from the last one written to go in: for video,
    /// half a frame at the capture rate; for audio, any later time.
    static func accepts(_ time: TimeInterval, after last: TimeInterval?, kind: Kind) -> Bool {
        guard let last else { return true }
        switch kind {
        case .video(let frameRate): return time >= last + 0.5 / Double(max(frameRate, 1))
        case .aac: return time > last
        }
    }

    /// Writes a buffer at a time on the recording's clock.
    public func append(_ buffer: CMSampleBuffer, at time: TimeInterval) {
        var failure: (any Error)?
        var firstOutOfOrder = false
        lock.withLock {
            let active: Active
            switch state {
            case .waiting:
                do {
                    active = try start(with: buffer, at: time)
                    state = .writing(active)
                } catch {
                    state = .failed(nil, error)
                    failure = error
                    return
                }
            case .writing(let current): active = current
            default: return
            }
            // A writer that failed between buffers is never ready for more, so check it first; otherwise the
            // failure would only come out at Stop.
            if active.writer.status == .failed {
                let error = active.writer.error ?? RecorderError.couldNotWrite(url, "the encoder failed")
                state = .failed(active, error)
                failure = error
                return
            }
            guard Self.accepts(time, after: last, kind: kind) else {
                outOfOrderCount += 1
                firstOutOfOrder = outOfOrderCount == 1
                return
            }
            guard active.input.isReadyForMoreMediaData else {
                droppedCount += 1
                return
            }
            let fallback: CMTime? = switch kind {
            case .video(let rate): CMTime(value: 1, timescale: Int32(clamping: max(1, rate)))
            case .aac: nil
            }
            guard let retimed = Self.retimed(buffer, to: CMTime(seconds: time, preferredTimescale: 48_000),
                                           fallbackDuration: fallback) else { return }
            if active.input.append(retimed) {
                last = time
                active.lastTime = max(active.lastTime, time + CMSampleBufferGetDuration(retimed).seconds.nonNaN)
            } else {
                let error = active.writer.error ?? RecorderError.couldNotWrite(url, "the encoder stopped accepting samples")
                state = .failed(active, error)
                failure = error
            }
        }
        if firstOutOfOrder {
            Self.log.notice("\(self.url.lastPathComponent, privacy: .public): dropped a buffer at \(time, privacy: .public) s that didn't move time on")
        }
        if let failure {
            let error = failure as NSError
            let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " (\($0.domain) \($0.code))" } ?? ""
            Self.log.error("\(self.url.lastPathComponent, privacy: .public) failed at \(time, privacy: .public) s: \(error.domain, privacy: .public) \(error.code, privacy: .public)\(underlying, privacy: .public) \(error.localizedDescription, privacy: .public)")
            lock.withLock { failureHandler }?(failure)
        }
    }

    /// Closes the file exactly once. Concurrent and repeated callers receive the same result.
    /// Once finalization starts, discard cannot delete a file another caller is finishing.
    /// A screen can stop sending new pictures while its content is unchanged. `holdingLastFrameUntil`
    /// keeps that picture through the stop time instead of shortening the take to its last change.
    public func finish(holdingLastFrameUntil end: TimeInterval? = nil) async throws -> Bool {
        let task: Task<Bool, Error> = lock.withLock {
            switch state {
            case .finishing(let task): return task
            case .finished(let result): return Task { try result.get() }
            case .cancelled: return Task { throw CancellationError() }
            case .waiting:
                state = .finished(.success(false))
                return Task { false }
            case .failed(let active, let error):
                let task = Task<Bool, Error> {
                    // Stop accepting buffers, but preserve any recoverable movie fragments.
                    // cancelWriting is reserved for an explicit discard: it deletes the output.
                    if let active, active.writer.status == .writing {
                        active.input.markAsFinished()
                        await active.writer.finishWriting()
                    }
                    throw error
                }
                state = .finishing(task)
                return task
            case .writing(let active):
                let finishTime: TimeInterval
                if case .video = kind, let end, end.isFinite {
                    finishTime = max(active.lastTime, end)
                } else {
                    finishTime = active.lastTime
                }
                let task = Task<Bool, Error> {
                    active.input.markAsFinished()
                    active.writer.endSession(atSourceTime: CMTime(seconds: finishTime, preferredTimescale: 48_000))
                    await active.writer.finishWriting()
                    guard active.writer.status == .completed else {
                        throw active.writer.error ?? RecorderError.couldNotWrite(self.url, "the encoder couldn't finish the file")
                    }
                    return true
                }
                state = .finishing(task)
                return task
            }
        }
        let result = await task.result
        lock.withLock {
            if case .finishing = state { state = .finished(result) }
        }
        return try result.get()
    }

    /// Discards a writer that has not begun finalizing. Repeated calls do nothing.
    public func cancel() {
        lock.withLock {
            let active: Active?
            switch state {
            case .waiting: active = nil
            case .writing(let value), .failed(let value?, _): active = value
            case .failed(nil, _): active = nil
            case .finishing, .finished, .cancelled: return
            }
            state = .cancelled
            active?.writer.cancelWriting()
        }
    }

    private func start(with buffer: CMSampleBuffer, at time: TimeInterval) throws -> Active {
        let fileType: AVFileType = url.pathExtension == "m4a" ? .m4a : .mov
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
        let input: AVAssetWriterInput
        switch kind {
        case .video(let frameRate):
            guard let format = CMSampleBufferGetFormatDescription(buffer) else { throw RecorderError.unexpectedBuffer }
            let size = CMVideoFormatDescriptionGetDimensions(format)
            input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: Int(size.width),
                    AVVideoHeightKey: Int(size.height),
                    AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: frameRate],
                ]
            )
        case .aac:
            input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000]
            )
        }
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.couldNotWrite(url, "the encoder wouldn't take this track") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecorderError.couldNotWrite(url, "the writer wouldn't start") }
        writer.startSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 48_000))
        first = time
        return Active(writer: writer, input: input, time: time)
    }

    /// A copy moved so its first sample plays at `time`. Live video can have no sample duration; give
    /// that frame one capture interval so finalization does not cut its last picture off at its start.
    static func retimed(_ buffer: CMSampleBuffer, to time: CMTime, fallbackDuration: CMTime? = nil) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(count, 1))
        CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        let shift = CMTimeSubtract(time, CMSampleBufferGetPresentationTimeStamp(buffer))
        for index in timings.indices {
            if let fallbackDuration, !timings[index].duration.seconds.isFinite || timings[index].duration.seconds <= 0 {
                timings[index].duration = fallbackDuration
            }
            timings[index].presentationTimeStamp = CMTimeAdd(timings[index].presentationTimeStamp, shift)
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp = CMTimeAdd(timings[index].decodeTimeStamp, shift)
            }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: buffer, sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &copy)
        return copy
    }
}

private extension Double {
    var nonNaN: Double { isFinite ? self : 0 }
}


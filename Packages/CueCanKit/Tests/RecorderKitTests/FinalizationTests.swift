import Foundation
import Testing
@testable import RecorderKit
import ProjectKit

struct FinalizationTests {
    private actor Calls {
        var names: [String] = []
        func record(_ name: String) { names.append(name) }
    }

    @Test func aFailedEncoderStillFinalizesTheCameraAndMic() async {
        let calls = Calls()
        let tracks: [RecordingFinalizer.Track] = [
            .init(kind: .screen, url: URL(filePath: "/tmp/screen.mov")) {
                await calls.record("screen")
                throw RecorderError.unexpectedBuffer
            },
            .init(kind: .camera, url: URL(filePath: "/tmp/camera.mov")) {
                await calls.record("camera")
                throw RecorderError.noCamera
            },
            .init(kind: .microphone, url: URL(filePath: "/tmp/mic.wav")) {
                await calls.record("mic")
                return 0.1
            },
        ]
        let (written, failed) = await RecordingFinalizer.finish(tracks)
        #expect(await calls.names == ["screen", "camera", "mic"])
        #expect(failed.map(\.kind) == [.screen, .camera])
        #expect(failed[0].message == RecorderError.unexpectedBuffer.localizedDescription)
        #expect(written.map(\.0) == [.microphone], "The mic is kept although the video failed.")
    }

    @Test func videoFramesMustMoveTimeOnByHalfAFrame() {
        let screen = TrackWriter.Kind.video(frameRate: 60)
        #expect(TrackWriter.accepts(1.0, after: nil, kind: screen))
        #expect(!TrackWriter.accepts(1.0, after: 1.0, kind: screen), "The same time twice.")
        #expect(!TrackWriter.accepts(0.99, after: 1.0, kind: screen), "Earlier than the last.")
        #expect(!TrackWriter.accepts(1.008, after: 1.0, kind: screen), "Less than half a frame at 60 fps.")
        #expect(TrackWriter.accepts(1.009, after: 1.0, kind: screen))
        #expect(TrackWriter.accepts(1.0001, after: 1.0, kind: .aac), "Audio only has to be later.")
        #expect(!TrackWriter.accepts(1.0, after: 1.0, kind: .aac))
    }

    @Test func aFailureSaysWhereTheTakeStopped() {
        let failure = TrackFailure(kind: .screen, at: 75.6, reason: "The operation could not be completed")
        #expect(failure.message().hasPrefix("The screen recording failed at 1:15, so CueCan stopped the take there."), "\(failure.message())")
        #expect(TrackFailure(kind: .microphone, at: 3_725, reason: "").message().contains("mic recording failed at 1:02:05"))
        #expect(!failure.message(saved: false).contains("saved"), "A take that couldn't be saved doesn't say it was.")
        #expect(TrackFailure.isStalled(lastFrame: 10, elapsed: 13.1, threshold: 3))
        #expect(!TrackFailure.isStalled(lastFrame: 10, elapsed: 12.9, threshold: 3))
        #expect(!TrackFailure.isStalled(lastFrame: nil, elapsed: 2, threshold: 3), "A camera has time to send its first frame.")
    }

    @Test func onlyTheFirstFailureIsReportedAndOnlyWhileRecording() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Failures")
        let session = try RecordingSession(project: folder, sources: .init())
        let reports = Calls()
        session.onTrackFailure { failure in Task { await reports.record(failure.trackName) } }
        session.trackFailed(.screen, reason: "before the take")
        #expect(!session.keepsCaptureAwake)
        session.start()
        #expect(session.keepsCaptureAwake)
        session.trackFailed(.screen, reason: "first")
        let stoppedAt = session.clock.elapsed
        #expect(session.clock.isPaused, "The capture clock stops without waiting for the UI's callback.")
        #expect(session.clock.place(RecordingClock.hostNow + 100) == nil)
        session.resume()
        #expect(session.clock.isPaused, "A failed session cannot be resumed.")
        session.trackFailed(.microphone, reason: "second")
        try await Task.sleep(for: .milliseconds(50))
        #expect(await reports.names == ["screen"])
        #expect(session.clock.elapsed == stoppedAt)
        #expect(session.trackFailure?.reason == "first")
        await #expect(throws: RecorderError.nothingRecorded) { try await session.stop() }
        #expect(!session.keepsCaptureAwake, "A failed finalization must release its sleep assertion.")
        #expect(session.trackFailure?.reason == "first", "Finalization retains the diagnostic.")
        session.discard()
    }

    @Test func aFailedMicIsRecoverableAndAnUnreadableVideoDoesNotLoseOtherTracks() async throws {
        let mic = URL(filePath: "/tmp/mic.wav"), screen = URL(filePath: "/tmp/screen.mov"), camera = URL(filePath: "/tmp/camera.mov")
        let recovered = await RecordingFinalizer.recover(written: [(.screen, screen, 0), (.camera, camera, 0.02)],
            failed: [.init(kind: .microphone, url: mic, message: "Couldn't close the WAV")],
            firstTimes: [.microphone: 0.01]) { kind, _ in
                if kind == .screen { throw RecorderError.unexpectedBuffer }
                return MediaInfo(duration: 2)
            }
        #expect(recovered.tracks.map(\.kind) == [.camera, .microphone])
        #expect(recovered.tracks.map(\.first) == [0.02, 0.01])
        #expect(recovered.lost.map(\.kind) == [.screen])
    }

    @Test func repeatedAndConcurrentFinishesOfAnEmptyWriterAgree() async throws {
        let writer = TrackWriter(url: URL(filePath: "/tmp/unused-\(UUID()).mov"), kind: .video(frameRate: 30))
        async let first = writer.finish()
        async let second = writer.finish()
        let results = try await [first, second]
        #expect(results == [false, false])
        writer.cancel()
        #expect(try await writer.finish() == false)
    }

    @Test func aDiscardedWriterCannotFinish() async {
        let writer = TrackWriter(url: URL(filePath: "/tmp/unused-\(UUID()).mov"), kind: .video(frameRate: 30))
        writer.cancel()
        writer.cancel()
        await #expect(throws: CancellationError.self) { try await writer.finish() }
    }

    @Test func stoppingAnEmptySessionTwiceHasTheSameFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Finalization")
        let session = try RecordingSession(project: folder, sources: .init())
        session.start()
        session.start()
        #expect(session.keepsCaptureAwake)
        await #expect(throws: RecorderError.nothingRecorded) { try await session.stop() }
        #expect(!session.keepsCaptureAwake)
        session.discard()
        await #expect(throws: RecorderError.nothingRecorded) { try await session.stop() }
    }

    @Test func pauseRetainsTheCaptureActivityAndDiscardReleasesIt() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-awake-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Capture activity")
        let session = try RecordingSession(project: folder, sources: .init())
        #expect(!session.keepsCaptureAwake)
        session.start()
        session.pause()
        #expect(session.keepsCaptureAwake, "Paused streams must remain available to resume.")
        session.resume()
        #expect(session.keepsCaptureAwake)
        session.discard()
        #expect(!session.keepsCaptureAwake)
        session.discard()
        session.start()
        #expect(!session.keepsCaptureAwake, "A discarded session cannot reacquire an activity.")
    }

}

import AVFoundation
import Foundation
import ProjectKit
import Testing
@testable import RenderKit

/// Exercise the playback pipeline as well as the reader/export pipeline: a poster alone cannot prove
/// that AVPlayer receives frames from the custom compositor.
@Suite(.serialized) struct PlayerPreviewTests {
    @Test(arguments: [1.0, 1.5, 2.0, 4.0, 8.0]) @MainActor func fractionalCutsPreservePlayback(rate: Double) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-player-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = try ProjectFolder.create(at: url, title: "Playback plumbing")
        try await SyntheticMedia.writeVideo(SyntheticMedia.red, width: 320, height: 180, seconds: 6,
                                            to: folder.url(for: .recordings).appending(path: "camera.mov"))
        try folder.updateProject { project in
            project.addSource(name: "Camera", origin: .recorded, tracks: [
                SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), startOffset: 0.00854900071863085,
                            media: MediaInfo(duration: 6, video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1")))
            ])
        }
        try folder.updateEdit(author: .app, reason: "Playback test") {
            $0.main = [clip(1, 0, 3.899545270133583), clip(2, 3.899545270133583, 6)]
            _ = try $0.setSpeed(try #require(ClipSpeed(rate: rate)), for: ClipID(number: 1))
        }
        let built = try await CompositionBuilder.build(try RenderInputs.load(folder), output: .landscape, scale: 0.25)
        let track = try #require(built.composition.tracks(withMediaType: .video).first)
        let segments = track.segments.filter { !$0.isEmpty }
        // One more than the clips: this camera starts 8.5 ms into the take, and holds its first frame until then.
        #expect(segments.first?.timeMapping.source.start == .zero && segments.first?.timeMapping.target.start == .zero)
        #expect(segments.count <= built.timeline.clips.count + 1, "A fractional cut must not split off an extra one-sample media segment.")
        for (before, after) in zip(segments, segments.dropFirst()) {
            #expect(before.timeMapping.target.end == after.timeMapping.target.start)
        }
        let item = built.makePlayerItem()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        defer { player.pause(); player.replaceCurrentItem(with: nil) }
        player.play()
        let deadline = ContinuousClock.now + .seconds(8)
        var receivedFrame = false
        while ContinuousClock.now < deadline, item.status != .failed {
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time), output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) != nil {
                receivedFrame = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(receivedFrame, "AVPlayer must deliver a frame, not merely report readyToPlay. Error: \(String(describing: item.error))")
    }
}

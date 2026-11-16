import CoreMedia
import Foundation

/// Watches a camera and listens to a mic for the sync page's flashes and beeps (docs/decisions.md, 83).
///
/// It taps the same buffers, with the same times, a recording writes, so what it measures is the gap a
/// take would have. Nothing is saved: frames are kept as a grid of brightness, and the sound only in
/// memory until ``stop()``.
public final class SyncCalibrator: @unchecked Sendable {
    /// How much of the picture and the sound is kept to look through, in seconds. What's found in it is
    /// kept for as long as the calibration runs, so it can listen as long as it takes.
    static let window: TimeInterval = 20
    /// How long a flash or a beep must have been over before it's counted, in seconds: the flash lasts
    /// 0.3 s and the beep 0.15 s, and one cut off by the window's end would be placed wrongly.
    static let settle: TimeInterval = 0.4
    /// Flashes or beeps nearer than this, found in two looks, are the same one, in seconds.
    static let same: TimeInterval = 0.3

    private let camera: CameraCapture
    private let mic: MicCapture
    private let lock = NSLock()
    private var frames: [BrightnessFrame] = []
    private var samples: [Float] = []
    /// How many samples have been dropped from the front of `samples`.
    private var droppedSamples = 0
    private var placement = SamplePlacement(sampleRate: MicCapture.sampleRate)
    private var unreadableFrames = 0
    private var foundFlashes: [TimeInterval] = []
    private var foundBeeps: [TimeInterval] = []

    public init(camera: CameraCapture, mic: MicCapture) {
        self.camera = camera
        self.mic = mic
    }

    /// Starts watching and listening. The camera and the mic must already be running.
    public func start() {
        lock.withLock {
            frames = []
            samples = []
            droppedSamples = 0
            placement = SamplePlacement(sampleRate: MicCapture.sampleRate)
            unreadableFrames = 0
            foundFlashes = []
            foundBeeps = []
        }
        camera.sink.set { [weak self] buffer, hostTime in
            guard let self, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
            let cells = FrameBrightness.cells(of: pixels)
            self.lock.withLock {
                if let cells { self.frames.append(BrightnessFrame(time: hostTime, cells: cells)) } else { self.unreadableFrames += 1 }
                if let first = self.frames.first, first.time < hostTime - Self.window {
                    self.frames.removeAll { $0.time < hostTime - Self.window }
                }
            }
        }
        mic.sink.set { [weak self] buffer, hostTime in
            guard let self else { return }
            let sound = MicCapture.floats(in: buffer)
            guard !sound.isEmpty else { return }
            self.lock.withLock {
                // Placed by its own time, as the mic's file is, so a dropped buffer doesn't shift what follows.
                let (silence, skip) = self.placement.place(count: sound.count, at: hostTime)
                if silence > 0 { self.samples.append(contentsOf: repeatElement(0, count: silence)) }
                self.samples.append(contentsOf: sound.dropFirst(skip))
                // Trimmed a few seconds at a time, so the sound isn't copied on every buffer.
                let kept = Int(Self.window * MicCapture.sampleRate)
                if self.samples.count > kept + Int(5 * MicCapture.sampleRate) {
                    let drop = self.samples.count - kept
                    self.samples.removeFirst(drop)
                    self.droppedSamples += drop
                }
            }
        }
    }

    /// Stops watching and listening, and forgets the sound.
    public func stop() {
        camera.sink.set(nil)
        mic.sink.set(nil)
        lock.withLock {
            frames = []
            samples = []
            foundFlashes = []
            foundBeeps = []
        }
    }

    /// Whether the camera is sending pictures in a format that can't be read for brightness.
    public var cameraIsUnreadable: Bool { lock.withLock { frames.isEmpty && unreadableFrames > 0 } }

    /// Everything seen and heard since ``start()``. It looks through what's been gathered, so call it off
    /// the main thread.
    public func measurement() -> SyncMeasurement {
        let (frames, samples, start) = lock.withLock {
            (self.frames, self.samples, placement.start.map { $0 + Double(droppedSamples) / MicCapture.sampleRate })
        }
        var flashes = FlashDetector.onsets(in: frames)
        if let last = frames.last?.time { flashes.removeAll { $0 > last - Self.settle } }
        var beeps: [TimeInterval] = []
        if let start {
            beeps = BeepDetector.onsets(in: samples, sampleRate: MicCapture.sampleRate, startTime: start)
            let end = start + Double(samples.count) / MicCapture.sampleRate
            beeps.removeAll { $0 > end - Self.settle }
        }
        return lock.withLock {
            Self.merge(flashes, into: &foundFlashes)
            Self.merge(beeps, into: &foundBeeps)
            return SyncMeasurement(flashes: foundFlashes, beeps: foundBeeps)
        }
    }

    /// Adds times not already found, in order. One found again in a later look keeps its first time.
    static func merge(_ new: [TimeInterval], into found: inout [TimeInterval]) {
        for time in new where !found.contains(where: { abs($0 - time) < same }) {
            found.append(time)
        }
        found.sort()
    }
}

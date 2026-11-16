import CoreVideo
import Foundation
import Testing
@testable import RecorderKit

/// Measuring how far the camera runs behind the mic from a phone's flashes and beeps
/// (docs/decisions.md, 83). Everything here is synthetic: it checks the arithmetic, not a real camera.
@Suite struct SyncCalibrationTests {
    // MARK: - Synthetic signals

    /// When the page would flash: uneven gaps, as the page's are.
    static let events: [TimeInterval] = [1.2, 3.03, 5.14, 7.11, 9.4]

    /// Frames from a camera whose exposure is half a frame long, centred on each frame's time. The phone
    /// covers the middle of the picture and is lit for 0.3 s from each flash.
    static func frames(flashes: [TimeInterval], rate: Double = 30, length: TimeInterval = 11, phase: TimeInterval = 0.004,
                       lit: Float = 0.8, dark: Float = 0.1) -> [BrightnessFrame] {
        let exposure = 0.5 / rate
        var frames: [BrightnessFrame] = []
        var time = phase
        var index = 0
        while time < length {
            let opens = time - exposure / 2, closes = time + exposure / 2
            var share = 0.0
            for flash in flashes {
                share += max(0, min(closes, flash + 0.3) - max(opens, flash)) / exposure
            }
            let phone = dark + (lit - dark) * Float(min(1, share))
            var cells = [Float](repeating: 0.35, count: FrameBrightness.columns * FrameBrightness.rows)
            for row in 2..<6 {
                for column in 4..<8 { cells[row * FrameBrightness.columns + column] = phone }
            }
            // Something else in the picture drifting a little, as a person does.
            cells[0] = 0.35 + 0.01 * Float(sin(Double(index) / 7))
            frames.append(BrightnessFrame(time: time, cells: cells))
            index += 1
            time = phase + Double(index) / rate
        }
        return frames
    }

    /// A mic's sound: quiet hiss, a low hum, and a 3 kHz beep of 0.15 s at each time.
    static func sound(beeps: [TimeInterval], length: TimeInterval = 11, rate: Double = 48_000, level: Float = 0.05,
                      frequency: Double = SyncSignal.beepFrequency) -> [Float] {
        var generator = SystemRandomNumberGenerator()
        var samples = (0..<Int(length * rate)).map { index in
            Float.random(in: -0.002...0.002, using: &generator) + 0.02 * Float(sin(2 * .pi * 180 * Double(index) / rate))
        }
        for beep in beeps {
            let first = Int((beep * rate).rounded())
            for index in 0..<Int(0.15 * rate) where first + index < samples.count {
                samples[first + index] += level * Float(sin(2 * .pi * frequency * Double(index) / rate))
            }
        }
        return samples
    }

    // MARK: - Flashes

    @Test func flashesAreFoundBetweenFrames() {
        let found = FlashDetector.onsets(in: Self.frames(flashes: Self.events))
        #expect(found.count == Self.events.count)
        for (found, event) in zip(found, Self.events) {
            #expect(abs(found - event) < 0.01, "A flash at \(event) was placed at \(found).")
        }
    }

    @Test func aFlashIsFoundWhateverThePhaseOfTheCamerasFrames() {
        for phase in stride(from: 0.0, to: 1.0 / 30, by: 0.004) {
            let found = FlashDetector.onsets(in: Self.frames(flashes: [2.0, 4.1], phase: phase))
            #expect(found.count == 2)
            for (found, event) in zip(found, [2.0, 4.1]) { #expect(abs(found - event) < 0.012, "phase \(phase)") }
        }
    }

    @Test func aSteadyPictureHasNoFlashes() {
        #expect(FlashDetector.onsets(in: Self.frames(flashes: [])).isEmpty)
    }

    @Test func aPhoneTooDimToTellIsNotAFlash() {
        #expect(FlashDetector.onsets(in: Self.frames(flashes: Self.events, lit: 0.13, dark: 0.1)).isEmpty)
    }

    @Test func oneBrightFrameIsNotAFlash() {
        var frames = Self.frames(flashes: [2.0])
        let stray = 150
        for cell in frames[stray].cells.indices where frames[stray].cells[cell] == 0.1 { frames[stray].cells[cell] = 0.8 }
        let found = FlashDetector.onsets(in: frames)
        #expect(found.count == 1)
        #expect(abs((found.first ?? 0) - 2.0) < 0.01)
    }

    // MARK: - Beeps

    @Test func beepsAreFoundToTheMillisecond() {
        let found = BeepDetector.onsets(in: Self.sound(beeps: Self.events), sampleRate: 48_000, startTime: 100)
        #expect(found.count == Self.events.count)
        for (found, event) in zip(found, Self.events) {
            #expect(abs(found - (100 + event)) < 0.0015, "A beep at \(event) was placed at \(found - 100).")
        }
    }

    @Test func soundWithoutTheBeepsPitchIsNotABeep() {
        // The same bursts an octave and a half down, and a loud knock.
        var samples = Self.sound(beeps: Self.events, frequency: 1_000)
        for index in 0..<96 { samples[48_000 * 6 + index] += index.isMultiple(of: 2) ? 0.6 : -0.6 }
        #expect(BeepDetector.onsets(in: samples, sampleRate: 48_000, startTime: 0).isEmpty)
    }

    @Test func aBeepTooQuietToTrustIsNotFound() {
        let samples = Self.sound(beeps: Self.events, level: 0.0005)
        #expect(BeepDetector.onsets(in: samples, sampleRate: 48_000, startTime: 0).isEmpty)
    }

    @Test func aKnockAmongTheBeepsIsLeftOut() {
        var samples = Self.sound(beeps: Self.events)
        // 5 ms of the beep's own pitch: too short to be a beep.
        for index in 0..<240 { samples[48_000 * 6 + index] += 0.05 * Float(sin(2 * .pi * 3_000 * Double(index) / 48_000)) }
        #expect(BeepDetector.onsets(in: samples, sampleRate: 48_000, startTime: 0).count == Self.events.count)
    }

    // MARK: - The measurement

    @Test func theCamerasDelayIsTheGapBetweenEachFlashAndItsBeep() throws {
        // The camera stamps each flash 83 ms after the mic stamps its beep.
        let delay = 0.083
        let flashes = FlashDetector.onsets(in: Self.frames(flashes: Self.events.map { $0 + delay }))
        let beeps = BeepDetector.onsets(in: Self.sound(beeps: Self.events), sampleRate: 48_000, startTime: 0)
        let measurement = SyncMeasurement(flashes: flashes, beeps: beeps)
        #expect(measurement.readings.count == 5)
        #expect(measurement.isComplete)
        #expect(abs(try #require(measurement.offset) - delay) < 0.008)
    }

    @Test func aCameraAheadOfTheMicMeasuresBelowZero() throws {
        let measurement = SyncMeasurement(flashes: [1.00, 3.00, 5.00], beeps: [1.02, 3.02, 5.02])
        #expect(abs(try #require(measurement.offset) + 0.02) < 1e-9)
        #expect(!measurement.isComplete)
    }

    @Test func aFlashWithNoBeepNearItGivesNoReading() {
        let measurement = SyncMeasurement(flashes: [1.0, 3.0, 5.0], beeps: [1.1, 4.0])
        #expect(measurement.readings.count == 1)
        #expect(measurement.flashes == 3)
        #expect(measurement.beeps == 2)
    }

    @Test func aStrayReadingIsLeftOutAndTheRestFinishIt() throws {
        // The fourth flash is 120 ms off: four agree, so it isn't finished until a fifth that agrees.
        var measurement = SyncMeasurement(flashes: [1.08, 3.09, 5.07, 7.20, 9.08], beeps: [1, 3, 5, 7, 9])
        #expect(measurement.agreeing.count == 4)
        #expect(!measurement.isComplete, "Five have to agree, not just five readings.")
        #expect(abs(try #require(measurement.offset) - 0.08) < 0.0051)
        measurement = SyncMeasurement(flashes: [1.08, 3.09, 5.07, 7.20, 9.08, 11.08], beeps: [1, 3, 5, 7, 9, 11])
        #expect(measurement.isComplete)
        #expect(abs(try #require(measurement.offset) - 0.08) < 1e-9)
    }

    @Test func nothingSeenIsNoOffset() {
        let measurement = SyncMeasurement(flashes: [], beeps: [1, 3])
        #expect(measurement.offset == nil)
        #expect(measurement.agreeing.isEmpty)
    }

    @Test func theSignalThatIsntArrivingIsNamed() {
        #expect(SyncMeasurement(flashes: [1, 3, 5], beeps: []).missing == .beep)
        #expect(SyncMeasurement(flashes: [], beeps: [1, 3, 5]).missing == .flash)
        #expect(SyncMeasurement(flashes: [1, 3], beeps: []).missing == nil, "Not until three of the other.")
        #expect(SyncMeasurement(flashes: [1, 3, 5], beeps: [9]).missing == nil)
    }

    @Test func aFlashFoundAgainInALaterLookIsCountedOnce() {
        var found: [TimeInterval] = [1.2, 3.03]
        SyncCalibrator.merge([3.031, 5.14, 1.199], into: &found)
        #expect(found == [1.2, 3.03, 5.14])
    }

    // MARK: - A frame's brightness

    @Test func aFramesBrightnessIsReadCellByCell() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 480, 320, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, 0)).assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        for y in 0..<320 {
            for x in 0..<480 { base[y * bytesPerRow + x] = x < 240 ? 255 : 51 }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])

        let cells = try #require(FrameBrightness.cells(of: pixels))
        #expect(cells.count == FrameBrightness.columns * FrameBrightness.rows)
        #expect(abs(cells[0] - 1) < 0.001)
        #expect(abs(cells[FrameBrightness.columns - 1] - 0.2) < 0.001)
        #expect(abs(cells[cells.count - 1] - 0.2) < 0.001)
    }

    @Test func aPixelFormatThatCantBeReadSaysSo() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 480, 320, kCVPixelFormatType_64RGBAHalf, nil, &buffer)
        #expect(FrameBrightness.cells(of: try #require(buffer)) == nil)
    }

    // MARK: - What's remembered

    @Test func aCalibrationIsRememberedForItsCameraAndMic() throws {
        var calibrations = SyncCalibrations()
        let measured = SyncCalibrations.Calibration(offset: 0.083, measuredAt: Date(timeIntervalSince1970: 1_800_000_000), readings: 5)
        calibrations.set(measured, camera: "camera-a", mic: "mic-a")
        #expect(calibrations.calibration(camera: "camera-a", mic: "mic-a") == measured)
        #expect(calibrations.calibration(camera: "camera-a", mic: "mic-b") == nil, "Another mic is another delay.")
        #expect(calibrations.calibration(camera: "camera-b", mic: "mic-a") == nil)

        let read = try JSONDecoder().decode(SyncCalibrations.self, from: JSONEncoder().encode(calibrations))
        #expect(read == calibrations)

        calibrations.set(nil, camera: "camera-a", mic: "mic-a")
        #expect(calibrations.calibration(camera: "camera-a", mic: "mic-a") == nil)
    }

    @Test func aDelaySetByHandIsKeptWithinWhatCouldBeMeasured() {
        let typed = SyncCalibrations.Calibration(byHandMilliseconds: 66)
        #expect(abs(typed.offset - 0.066) < 1e-9)
        #expect(typed.milliseconds == 66)
        #expect(typed.isSetByHand)
        #expect(SyncCalibrations.Calibration(byHandMilliseconds: -40).milliseconds == -40, "A camera ahead of the mic is below zero.")
        #expect(SyncCalibrations.Calibration(byHandMilliseconds: 9_000).milliseconds == 500)
        #expect(SyncCalibrations.Calibration(byHandMilliseconds: -9_000).milliseconds == -500)
        #expect(!SyncCalibrations.Calibration(offset: 0.083, measuredAt: .now, readings: 5).isSetByHand)
    }
}

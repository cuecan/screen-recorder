import Foundation

/// How far the camera runs behind the mic, from the sync page's flashes and beeps (docs/decisions.md, 83).
///
/// The phone flashes and beeps at one instant. The camera's frames and the mic's sound are both stamped on
/// the Mac's clock, so the gap between where a flash and its beep were stamped is the gap a recording has.
public struct SyncMeasurement: Sendable, Equatable {
    /// The signal a calibration isn't picking up.
    public enum Signal: Sendable, Equatable {
        case flash, beep
    }

    /// One reading per flash that has a beep: the flash's time less the beep's, in seconds. Above zero, the
    /// camera is behind the mic.
    public var readings: [TimeInterval]
    /// How many flashes were seen and beeps heard, paired or not.
    public var flashes: Int
    public var beeps: Int

    /// Pairs each flash with the beep nearest it, no further than `maximumOffset` away. A beep is used once.
    public init(flashes: [TimeInterval], beeps: [TimeInterval], maximumOffset: TimeInterval = SyncSignal.maximumOffset) {
        var unused = beeps
        var readings: [TimeInterval] = []
        for flash in flashes {
            guard let nearest = unused.indices.min(by: { abs(unused[$0] - flash) < abs(unused[$1] - flash) }),
                  abs(unused[nearest] - flash) <= maximumOffset else { continue }
            readings.append(flash - unused[nearest])
            unused.remove(at: nearest)
        }
        self.readings = readings
        self.flashes = flashes.count
        self.beeps = beeps.count
    }

    /// The readings that agree: those within ``SyncSignal/agreement`` of the middle reading. A stray one,
    /// such as a flash paired with the wrong beep, is left out rather than spoiling the rest.
    public var agreeing: [TimeInterval] {
        guard let middle = Self.median(readings) else { return [] }
        return readings.filter { abs($0 - middle) <= SyncSignal.agreement }
    }

    /// Whether enough readings agree to stop: the calibration is then saved without asking.
    public var isComplete: Bool { agreeing.count >= SyncSignal.readingsWanted }

    /// How far the camera is behind the mic, in seconds: the middle of the readings that agree. Nil with
    /// no readings.
    public var offset: TimeInterval? { Self.median(agreeing) }

    /// The signal that isn't arriving while the other is, to say which to fix. Nil while both are, or
    /// before either has arrived often enough to tell.
    public var missing: Signal? {
        if flashes >= SyncSignal.missingAfter, beeps == 0 { return .beep }
        if beeps >= SyncSignal.missingAfter, flashes == 0 { return .flash }
        return nil
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

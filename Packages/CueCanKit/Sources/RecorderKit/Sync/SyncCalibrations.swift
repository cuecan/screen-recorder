import Foundation

/// The camera's measured delay behind the mic, remembered for each pair of camera and mic
/// (docs/decisions.md, 83). A new take's camera track is moved by it.
///
/// It's kept per pair because the delay is the camera's path less the mic's: another camera, or the same
/// camera with another mic, is another delay.
public struct SyncCalibrations: Codable, Equatable, Sendable {
    public struct Calibration: Codable, Equatable, Sendable {
        /// How far the camera is behind the mic, in seconds. Below zero, it's ahead.
        public var offset: TimeInterval
        public var measuredAt: Date
        /// How many flashes it was measured from. None when it was set by hand.
        public var readings: Int

        public init(offset: TimeInterval, measuredAt: Date, readings: Int) {
            self.offset = offset
            self.measuredAt = measuredAt
            self.readings = readings
        }

        /// A delay typed in by the creator, in milliseconds, kept within what a measurement could find
        /// (``SyncSignal/maximumOffset``).
        public init(byHandMilliseconds milliseconds: Int, at date: Date = .now) {
            let limit = Self.limitMilliseconds
            self.init(offset: Double(min(limit, max(-limit, milliseconds))) / 1000, measuredAt: date, readings: 0)
        }

        /// The furthest a delay can be set by hand, either way, in milliseconds.
        public static var limitMilliseconds: Int { Int((SyncSignal.maximumOffset * 1000).rounded()) }

        /// Whether the creator typed it in, not measured it.
        public var isSetByHand: Bool { readings == 0 }

        /// The delay to the nearest millisecond, as it's shown and typed.
        public var milliseconds: Int { Int((offset * 1000).rounded()) }
    }

    public static let storageKey = "syncCalibrations"
    private var pairs: [String: Calibration]

    public init() { pairs = [:] }

    /// The calibration for a camera and a mic, by their device ids.
    public func calibration(camera: String, mic: String) -> Calibration? {
        pairs[Self.key(camera: camera, mic: mic)]
    }

    /// Remembers a pair's calibration, or forgets it with nil.
    public mutating func set(_ calibration: Calibration?, camera: String, mic: String) {
        pairs[Self.key(camera: camera, mic: mic)] = calibration
    }

    private static func key(camera: String, mic: String) -> String { "\(camera)\n\(mic)" }

    /// What's remembered in the app's preferences.
    public static func load(from defaults: UserDefaults = .standard) -> SyncCalibrations {
        defaults.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(SyncCalibrations.self, from: $0) } ?? SyncCalibrations()
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

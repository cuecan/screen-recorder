import Foundation

/// How the level meter moves: it rises at once to a louder peak and falls back slowly, the way a hardware
/// meter does, so it reads as a level instead of flickering with every 20 ms window.
///
/// It also holds its loudest recent peak, drawn as a mark on the meter: the peak stays put for
/// ``holdDuration`` after it's reached, then falls at the same rate, so a clip stays visible long enough to
/// see (docs/decisions.md, 18). It's the meter's whole job now there's no waveform.
///
/// The fall rate is a starting value, to judge by eye: 20 dB a second, close to a broadcast peak meter's. The
/// hold is a starting value too (AUTHOR'S TAKE NEEDED).
public struct LevelBallistics: Sendable, Equatable {
    public var fallRate: Float
    /// How long the held peak stays before it falls.
    public var holdDuration: TimeInterval
    /// What the meter shows now, in dBFS.
    public private(set) var decibels: Float = -120
    /// The held peak, in dBFS.
    public private(set) var peakDecibels: Float = -120
    private enum PeakState: Sendable, Equatable {
        case holding(remaining: TimeInterval)
        case falling
    }
    private var peakState = PeakState.falling

    public init(fallRate: Float = 20, holdDuration: TimeInterval = 1.5) {
        self.fallRate = fallRate
        self.holdDuration = holdDuration
    }

    /// Takes the next windows and returns what the meter shows after them.
    @discardableResult
    public mutating func observe(_ samples: [LevelSample], windowDuration: TimeInterval = LevelAnalyzer.windowDuration) -> Float {
        for sample in samples {
            let fallen = decibels - fallRate * Float(windowDuration)
            decibels = max(sample.peakDecibels, max(-120, fallen))
            if sample.peakDecibels >= peakDecibels {
                peakDecibels = sample.peakDecibels
                peakState = .holding(remaining: max(0, holdDuration))
            } else {
                let fallDuration: TimeInterval
                switch peakState {
                case .holding(let remaining):
                    if remaining >= windowDuration {
                        peakState = .holding(remaining: remaining - windowDuration)
                        fallDuration = 0
                    } else {
                        peakState = .falling
                        fallDuration = windowDuration - remaining
                    }
                case .falling:
                    fallDuration = windowDuration
                }
                peakDecibels = max(decibels, max(-120, peakDecibels - fallRate * Float(fallDuration)))
            }
        }
        return decibels
    }

    public mutating func reset() {
        decibels = -120
        peakDecibels = -120
        peakState = .falling
    }
}

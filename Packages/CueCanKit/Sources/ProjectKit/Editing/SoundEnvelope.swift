import Foundation

/// A voice's loudness over its source's time, one level in dB for each short frame, for finding quiet places
/// to cut (docs/decisions.md, 74). It comes from the audio itself, so it's trusted over word times.
public struct SoundEnvelope: Sendable, Equatable {
    /// Each frame's level, in dB.
    public let levels: [Double]
    public let frameDuration: TimeInterval
    /// The source time frame 0 starts at.
    public let start: TimeInterval

    /// How much quieter than the sound either side a dip must be to count, in dB.
    public static let dipDepth = 6.0
    /// How far either side of a dip to look for the louder sound around it, in seconds.
    public static let dipReach = 0.15

    public init(levels: [Double], frameDuration: TimeInterval, start: TimeInterval = 0) {
        self.levels = levels
        self.frameDuration = frameDuration > 0 ? frameDuration : 0.01
        self.start = start
    }

    public var end: TimeInterval { start + Double(levels.count) * frameDuration }

    /// The frame a source time falls in, which may be outside the levels.
    public func frame(at time: TimeInterval) -> Int {
        Int(((time - start) / frameDuration).rounded(.down))
    }

    /// The source time at a frame's middle.
    public func time(ofFrame frame: Int) -> TimeInterval {
        start + (Double(frame) + 0.5) * frameDuration
    }

    /// The level of a frame, or nil outside the levels.
    public func level(ofFrame frame: Int) -> Double? {
        levels.indices.contains(frame) ? levels[frame] : nil
    }

    /// Frames whose middles fall inside a stretch of source time.
    public func frames(in range: TimeRange) -> ClosedRange<Int>? {
        let first = max(0, Int(((range.start - start) / frameDuration - 0.5).rounded(.up)))
        let last = min(levels.count - 1, Int(((range.end - start) / frameDuration - 0.5).rounded(.down)))
        return first <= last ? first...last : nil
    }

    /// The bottom of the deepest dip in a stretch of source time: the quietest frame there that's no louder
    /// than its neighbours and at least `depth` dB quieter than the loudest sound within `reach` on each
    /// side. A gap between words, or between syllables, is such a dip; the flat quiet of a silence isn't.
    /// Nil when the stretch has none. Of two equally quiet bottoms, the one nearer `near` wins.
    public func dip(in range: TimeRange, near: TimeInterval? = nil, depth: Double = dipDepth, reach: TimeInterval = dipReach) -> TimeInterval? {
        guard let frames = frames(in: range) else { return nil }
        let middle = near ?? (range.start + range.end) / 2
        let ordered = frames.sorted { a, b in
            if levels[a] != levels[b] { return levels[a] < levels[b] }
            return abs(time(ofFrame: a) - middle) < abs(time(ofFrame: b) - middle)
        }
        return ordered.first { isDip($0, depth: depth, reach: reach) }.map(time(ofFrame:))
    }

    /// The bottom of the dip nearest a source time, looking only one way: later when `forward`, else earlier,
    /// up to `within` seconds. Nil when there's none that far.
    public func nearestDip(from time: TimeInterval, forward: Bool, within: TimeInterval, depth: Double = dipDepth,
                           reach: TimeInterval = dipReach) -> TimeInterval? {
        let steps = Int((within / frameDuration).rounded(.down))
        let first = forward ? frame(at: time + frameDuration / 2) : frame(at: time - frameDuration / 2)
        for step in 0..<max(0, steps) {
            let frame = forward ? first + step : first - step
            guard levels.indices.contains(frame) else { return nil }
            if isDip(frame, depth: depth, reach: reach) { return self.time(ofFrame: frame) }
        }
        return nil
    }

    /// Whether a frame is the bottom of a dip: no louder than its neighbours, and at least `depth` dB quieter
    /// than the loudest sound within `reach` seconds on each side.
    public func isDip(_ frame: Int, depth: Double = dipDepth, reach: TimeInterval = dipReach) -> Bool {
        guard levels.indices.contains(frame) else { return false }
        let reachFrames = max(1, Int((reach / frameDuration).rounded()))
        let level = levels[frame]
        guard level <= (self.level(ofFrame: frame - 1) ?? .infinity), level <= (self.level(ofFrame: frame + 1) ?? .infinity) else { return false }
        let before = levels[max(0, frame - reachFrames)..<frame].max() ?? level
        let after = levels[min(levels.count, frame + 1)..<min(levels.count, frame + reachFrames + 1)].max() ?? level
        return min(before, after) - level >= depth
    }

    /// A frame's level averaged with its neighbours', so a single odd frame doesn't stand out. Nil outside
    /// the levels.
    public func smoothedLevel(ofFrame frame: Int) -> Double? {
        guard levels.indices.contains(frame) else { return nil }
        let around = [frame - 1, frame, frame + 1].compactMap(level(ofFrame:))
        return around.reduce(0, +) / Double(around.count)
    }

    /// The smoothed level at a source time, or nil outside the levels.
    public func smoothedLevel(at time: TimeInterval) -> Double? {
        smoothedLevel(ofFrame: frame(at: time))
    }

    /// The middle of the quietest frame between two source times, by smoothed level. Of equally quiet frames,
    /// the one nearest `near` wins. Nil when no frame's middle falls between them.
    public func quietest(in range: TimeRange, near: TimeInterval? = nil) -> TimeInterval? {
        guard let frames = frames(in: range) else { return nil }
        let middle = near ?? (range.start + range.end) / 2
        let best = frames.min { a, b in
            let levelA = smoothedLevel(ofFrame: a) ?? 0, levelB = smoothedLevel(ofFrame: b) ?? 0
            if levelA != levelB { return levelA < levelB }
            return abs(time(ofFrame: a) - middle) < abs(time(ofFrame: b) - middle)
        }
        return best.map(time(ofFrame:))
    }
}

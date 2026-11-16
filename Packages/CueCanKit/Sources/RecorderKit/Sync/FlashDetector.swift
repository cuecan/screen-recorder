import Foundation

/// One camera frame's brightness: the picture cut into a grid, each cell its mean brightness from 0 to 1.
public struct BrightnessFrame: Sendable, Equatable {
    /// When the frame was taken, on the host clock, as its track would be stamped in a recording.
    public var time: TimeInterval
    public var cells: [Float]

    public init(time: TimeInterval, cells: [Float]) {
        self.time = time
        self.cells = cells
    }
}

/// Finds when a phone's screen flashed white in front of the camera (docs/decisions.md, 83).
///
/// No model: only the part of the picture that flashes is looked at, and a flash is where its brightness
/// steps up. A frame gathers light for a while, so the frame a flash starts in is only partly lit; the
/// flash is placed where the brightness crosses halfway, between that frame and the one before. What a
/// frame's time means inside its exposure isn't known, so one reading is good to about half a frame.
public enum FlashDetector {
    /// The least the flashing part of the picture has to brighten, of full scale. A starting value.
    public static let minimumRise = 0.06
    /// Flashes closer together than this are one flash, in seconds.
    static let refractory = 0.8

    /// When each flash began.
    public static func onsets(in frames: [BrightnessFrame]) -> [TimeInterval] {
        guard let levels = levels(of: frames) else { return [] }
        return onsets(times: frames.map(\.time), levels: levels)
    }

    /// The brightness, frame by frame, of the cells that flash: those that get at least half as far above
    /// their usual brightness as the cell that gets furthest. Nil when nothing in the picture swings enough to be a flash.
    static func levels(of frames: [BrightnessFrame]) -> [Double]? {
        guard let count = frames.first?.cells.count, count > 0, frames.count >= 8,
              frames.allSatisfy({ $0.cells.count == count }) else { return nil }
        var swings = [Double](repeating: 0, count: count)
        for cell in 0..<count {
            let sorted = frames.map { Double($0.cells[cell]) }.sorted()
            swings[cell] = bright(sorted) - percentile(sorted, 0.5)
        }
        guard let widest = swings.max(), widest >= minimumRise else { return nil }
        let flashing = swings.indices.filter { swings[$0] >= widest / 2 }
        return frames.map { frame in
            flashing.reduce(0.0) { $0 + Double(frame.cells[$1]) } / Double(flashing.count)
        }
    }

    /// When each step up in `levels` began: where it crosses halfway from its level before to its peak.
    static func onsets(times: [TimeInterval], levels: [Double]) -> [TimeInterval] {
        guard times.count == levels.count, levels.count >= 8 else { return [] }
        let sorted = levels.sorted()
        let low = percentile(sorted, 0.5)
        let rise = bright(sorted) - low
        guard rise >= minimumRise else { return [] }
        let middle = low + rise / 2

        var onsets: [TimeInterval] = []
        for index in 1..<levels.count where levels[index] >= middle && levels[index - 1] < middle {
            if let last = onsets.last, times[index] - last < refractory { continue }
            // The level just before this flash, and its peak just after.
            let before = levels.indices.filter { times[$0] >= times[index] - 0.4 && times[$0] <= times[index] - 0.07 }
            let after = levels.indices.filter { times[$0] >= times[index] && times[$0] <= times[index] + 0.2 }
            let floor = before.count >= 3 ? percentile(before.map { levels[$0] }.sorted(), 0.5) : low
            guard let peak = after.map({ levels[$0] }).max(), peak - floor >= minimumRise else { continue }
            let half = floor + (peak - floor) / 2
            // A flash lasts several frames; one bright frame alone is something else.
            if index + 1 < levels.count, levels[index + 1] < half { continue }
            let start = max(1, index - 3)
            guard let crossing = (start...min(levels.count - 1, index + 2)).first(where: { levels[$0] >= half && levels[$0 - 1] < half }) else { continue }
            let fraction = (half - levels[crossing - 1]) / (levels[crossing] - levels[crossing - 1])
            onsets.append(times[crossing - 1] + fraction * (times[crossing] - times[crossing - 1]))
        }
        return onsets
    }

    /// How bright sorted values get: the third brightest, so one flash of a few frames counts, however long
    /// the wait around it, and a stray bright frame or two doesn't.
    static func bright(_ sorted: [Double]) -> Double {
        sorted.count >= 3 ? sorted[sorted.count - 3] : (sorted.last ?? 0)
    }

    /// The value a fraction of the way through sorted values.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard let last = sorted.last else { return 0 }
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return index < sorted.count ? sorted[index] : last
    }
}

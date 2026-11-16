import CoreGraphics
import Foundation

/// Caption animation as plain functions of time: a damped spring on scale and an ease on opacity, no keyframes
/// (docs/decisions.md, 80). A frame asks where things are at its time, so a cut or a word fix moves the motion
/// with the words.
public enum CaptionMotion {
    /// A pop starts at this fraction of its size.
    public static let popFrom = 0.7
    /// A rise starts this many text sizes below its place.
    public static let riseFrom = 0.35
    /// How long the box takes to glide from one word to the next.
    public static let boxGlide: TimeInterval = 0.09

    /// An under-damped spring from 0 at `t = 0` to 1, overshooting before it settles. 0 before `t = 0`.
    public static func spring(_ t: TimeInterval, _ spring: CaptionStyle.Spring) -> Double {
        guard t > 0 else { return 0 }
        let damping = min(max(spring.damping, 0), 0.999)
        let omega = 2 * Double.pi / max(spring.period, 0.001)
        let decay = damping * omega
        let damped = omega * (1 - damping * damping).squareRoot()
        return 1 - exp(-decay * t) * (cos(damped * t) + decay / damped * sin(damped * t))
    }

    /// How far past 1 a spring with this damping overshoots, at its first peak.
    public static func overshoot(damping: Double) -> Double {
        let damping = min(max(damping, 0), 0.999)
        return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
    }

    /// Eases out from 0 to 1 over `duration`, cubically. 0 before `t = 0`.
    public static func easeOut(_ t: TimeInterval, over duration: TimeInterval) -> Double {
        guard duration > 0 else { return t >= 0 ? 1 : 0 }
        let x = min(1, max(0, t / duration))
        return 1 - (1 - x) * (1 - x) * (1 - x)
    }

    /// Eases in and out from 0 to 1 over `duration`.
    public static func easeInOut(_ t: TimeInterval, over duration: TimeInterval) -> Double {
        guard duration > 0 else { return t >= 0 ? 1 : 0 }
        let x = min(1, max(0, t / duration))
        return x * x * (3 - 2 * x)
    }

    /// How something is drawn at a moment: its opacity, a scale about its middle, and how far below its place
    /// it is, in text sizes.
    public struct State: Equatable, Sendable {
        public var opacity: Double
        public var scale: Double
        public var drop: Double

        public static let rest = State(opacity: 1, scale: 1, drop: 0)
    }

    /// Coming in with a motion, `since` seconds after it started.
    public static func entering(since: TimeInterval, _ entrance: CaptionStyle.Entrance, spring: CaptionStyle.Spring) -> State {
        guard since >= 0 else { return State(opacity: 0, scale: 1, drop: 0) }
        let fade = easeOut(since, over: entrance.duration)
        switch entrance.motion {
        case .none: return .rest
        case .fade: return State(opacity: fade, scale: 1, drop: 0)
        case .pop: return State(opacity: fade, scale: popFrom + (1 - popFrom) * self.spring(since, spring), drop: 0)
        case .rise: return State(opacity: fade, scale: 1, drop: riseFrom * (1 - easeOut(since, over: entrance.duration * 2)))
        }
    }

    /// How a whole page is drawn: entering if the style brings the page in at once, fading out as it ends.
    public static func page(at time: TimeInterval, show: TimeRange, style: CaptionStyle) -> State {
        var state = style.entrance.reveal == .page ? entering(since: time - show.start, style.entrance, spring: style.spring) : .rest
        state.opacity *= easeOut(show.end - time, over: style.entrance.exit)
        return state
    }

    /// How one word is drawn on its own, apart from the page: entering when the style brings words in one by
    /// one, and its scale while it's being said.
    public static func word(at time: TimeInterval, index: Int, of page: CaptionPage, style: CaptionStyle) -> State {
        let turn = page.turn(of: index)
        var state = style.entrance.reveal == .word ? entering(since: time - turn.start, style.entrance, spring: style.spring) : .rest
        if style.spoken.reach != .none, style.spoken.scale != 1 {
            let rise = spring(time - turn.start, style.spring)
            let fall = spring(time - turn.end, style.spring)
            state.scale *= 1 + (style.spoken.scale - 1) * (rise - fall)
        }
        return state
    }

    /// Whether a word is marked as being said at a moment.
    public static func isMarked(_ index: Int, spoken: Int?, reach: CaptionStyle.Spoken.Reach) -> Bool {
        guard let spoken else { return false }
        switch reach {
        case .none: return false
        case .word: return index == spoken
        case .throughWord: return index <= spoken
        }
    }

    /// Where the box behind the word being said is, between the previous word's rectangle and the current one's,
    /// gliding over ``boxGlide`` from the current word's start. Nil before the first word.
    public static func box(at time: TimeInterval, page: CaptionPage, rects: [CGRect]) -> CGRect? {
        guard let spoken = page.spokenIndex(at: time), rects.indices.contains(spoken) else { return nil }
        let target = rects[spoken]
        guard spoken > 0, rects.indices.contains(spoken - 1) else { return target }
        let from = rects[spoken - 1]
        // Gliding to another line looks like a swoop across the page; jump instead.
        guard abs(from.midY - target.midY) < target.height / 2 else { return target }
        let x = CGFloat(easeInOut(time - page.words[spoken].timeline.start, over: boxGlide))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * x }
        return CGRect(x: mix(from.minX, target.minX), y: mix(from.minY, target.minY),
                      width: mix(from.width, target.width), height: mix(from.height, target.height))
    }
}

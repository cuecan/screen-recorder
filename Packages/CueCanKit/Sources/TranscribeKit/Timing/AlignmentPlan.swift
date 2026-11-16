import Foundation

/// How a long recording is placed a stretch at a time (``WordTimer``).
///
/// Placing known words needs the whole stretch they were said in, and a recording of hours can't be held at
/// once. So each of the model's windows is placed together with the window before and the window after it:
/// the words of all three are placed, and only the middle window's are kept. A kept word is then always at
/// least a window away from where the stretch was cut, so what happens at the cut can't reach it.
public enum AlignmentPlan {
    /// One stretch to place.
    public struct Span: Equatable, Sendable {
        /// The model's windows whose frames are used.
        public var windows: Range<Int>
        /// The words placed in it, by index.
        public var words: Range<Int>
        /// The words whose new times are kept: the ones that start in the middle window.
        public var kept: Range<Int>
    }

    /// How far inside a stretch's cut edges a word has to start to be placed in it, in seconds: a word nearer
    /// the cut may have part of its sound outside the stretch.
    public static let margin: TimeInterval = 1.5

    /// - Parameters:
    ///   - starts: Each word's rough start, in order (Parakeet's).
    ///   - duration: The recording's length in seconds.
    ///   - window: The model's window, in seconds.
    public static func spans(starts: [TimeInterval], duration: TimeInterval, window: TimeInterval) -> [Span] {
        guard !starts.isEmpty, duration > 0, window > 0 else { return [] }
        let count = max(1, Int((duration / window).rounded(.up)))
        var spans: [Span] = []
        for middle in 0..<count {
            let first = max(0, middle - 1), last = min(count - 1, middle + 1)
            let from = first == 0 ? -TimeInterval.infinity : TimeInterval(first) * window + margin
            let to = last == count - 1 ? TimeInterval.infinity : TimeInterval(last + 1) * window - margin
            let coreFrom = middle == 0 ? -TimeInterval.infinity : TimeInterval(middle) * window
            let coreTo = middle == count - 1 ? TimeInterval.infinity : TimeInterval(middle + 1) * window
            let words = range(of: starts) { $0 >= from && $0 < to }
            let kept = range(of: starts) { $0 >= coreFrom && $0 < coreTo }
            guard !kept.isEmpty else { continue }
            spans.append(Span(windows: first..<(last + 1), words: words, kept: kept))
        }
        return spans
    }

    /// The run of indices whose value passes. The values are in order, so the ones that pass are together.
    private static func range(of values: [TimeInterval], where passes: (TimeInterval) -> Bool) -> Range<Int> {
        guard let first = values.firstIndex(where: passes) else { return 0..<0 }
        let end = values[first...].firstIndex { !passes($0) } ?? values.count
        return first..<end
    }
}

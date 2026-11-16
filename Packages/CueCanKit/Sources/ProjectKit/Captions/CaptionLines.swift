import Foundation

/// Wraps a page's words into lines, as pure maths on their widths, so it's tested without drawing.
public enum CaptionLines {
    /// Each line's word indices: as many words as fit in `maximumWidth`, in order, breaking where a word asks
    /// to start a line. A word wider than a line stands alone on it. When the greedy fill leaves the last line
    /// much shorter, words move down so the last two lines are as even as they can be.
    public static func wrap(widths: [Double], startsLine: [Bool], space: Double, maximumWidth: Double) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var used = 0.0
        for (index, width) in widths.enumerated() {
            let asked = startsLine.indices.contains(index) && startsLine[index]
            if !current.isEmpty, asked || used + space + width > maximumWidth {
                lines.append(current)
                current = []
                used = 0
            }
            used += (current.isEmpty ? 0 : space) + width
            current.append(index)
        }
        if !current.isEmpty { lines.append(current) }
        // Evening out would move a word past a break someone asked for.
        guard lines.count >= 2, !startsLine.contains(true) else { return lines }
        return balanced(lines, widths: widths, space: space)
    }

    /// A line's width.
    public static func width(of line: [Int], widths: [Double], space: Double) -> Double {
        line.map { widths[$0] }.reduce(0, +) + space * Double(max(0, line.count - 1))
    }

    /// Moves words from the second-to-last line down to the last while that makes the longer of the two shorter.
    static func balanced(_ lines: [[Int]], widths: [Double], space: Double) -> [[Int]] {
        var before = lines[lines.count - 2]
        var last = lines[lines.count - 1]
        var best = max(width(of: before, widths: widths, space: space), width(of: last, widths: widths, space: space))
        while before.count > 1 {
            let rest = Array(before.dropLast())
            let moved = [before[before.count - 1]] + last
            let candidate = max(width(of: rest, widths: widths, space: space), width(of: moved, widths: widths, space: space))
            guard candidate < best else { break }
            best = candidate
            before = rest
            last = moved
        }
        return Array(lines.dropLast(2)) + [before, last]
    }
}

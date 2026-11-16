import Foundation

/// Turns ranges of word and silence ids into source times that land in real silences.
///
/// Every pair of neighbouring items in a transcript has one boundary, and every cut between them happens
/// there, whichever side is kept. So cutting a range and then keeping it again puts back exactly what
/// was there. The boundary depends on what the two items are:
///
/// - **A word, then a silence:** ``SnapSettings/trailPad`` into the silence, so the word's tail fades out.
/// - **A silence, then a word:** ``SnapSettings/leadPad`` before the silence ends, so the word's first
///   sound isn't clipped.
/// - **Two words with no silence between them:** halfway between the first's end and the second's start.
///   There's no quiet place to cut, so this is the least bad one.
///
/// When a silence is shorter than the two pads together, both of its boundaries meet at one point,
/// splitting it in the pads' ratio. The word before keeps the larger share when its trail pad is the
/// larger, as it is by default, because a word's tail fades out more slowly than its start. Neighbouring
/// clips then share one edge instead of both playing part of the pause.
///
/// The silence's own times win over a word's aligned times, because the silence comes from the audio and
/// aligned times can be off.
public struct CutPointSnapper: Sendable {
    public let transcript: Transcript
    public let settings: SnapSettings

    public init(transcript: Transcript, settings: SnapSettings = .default) {
        self.transcript = transcript
        self.settings = settings
    }

    private var items: [TranscriptItem] { transcript.items }

    /// The cut point between item `index - 1` and item `index`. Index 0 is the boundary before the first
    /// item, and `items.count` the boundary after the last.
    public func boundary(before index: Int) -> TimeInterval {
        precondition((0...items.count).contains(index), "Boundary index \(index) is outside the transcript.")
        let before = index > 0 ? items[index - 1] : nil
        let after = index < items.count ? items[index] : nil

        switch (before, after) {
        case (nil, nil):
            return 0
        case (nil, .silence(let silence)?):
            return silence.start
        case (nil, .word(let word)?):
            return max(0, word.start - settings.leadPad)
        case (.silence(let silence)?, nil):
            return silence.end
        case (.word(let word)?, nil):
            return min(transcript.audioDuration, word.end + settings.trailPad)
        case (.word?, .silence(let silence)?):
            return sharedEdge(in: silence) ?? min(silence.start + settings.trailPad, silence.end)
        case (.silence(let silence)?, .word?):
            return sharedEdge(in: silence) ?? max(silence.end - settings.leadPad, silence.start)
        case (.word(let first)?, .word(let second)?):
            return (first.end + second.start) / 2
        case (.silence(let first)?, .silence(let second)?):
            return (first.end + second.start) / 2
        }
    }

    /// Where both boundaries of a silence too short for both pads meet, or nil when the pads fit.
    private func sharedEdge(in silence: Silence) -> TimeInterval? {
        let pads = settings.leadPad + settings.trailPad
        guard silence.duration < pads else { return nil }
        return silence.start + silence.duration * settings.trailPad / pads
    }

    /// The positions of a range's first and last items, checking that both are in this transcript and in
    /// spoken order.
    public func indices(of range: ItemRange) throws(EditError) -> ClosedRange<Int> {
        guard let first = transcript.index(of: range.first) else {
            throw .unknownItem(range.first)
        }
        guard let last = transcript.index(of: range.last) else {
            throw .unknownItem(range.last)
        }
        guard first <= last else {
            throw .rangeOutOfOrder(range)
        }
        return first...last
    }

    /// The source time a range of items covers: from the boundary before its first item to the boundary
    /// after its last. Keeping the range plays this, and cutting the range takes this out. It's empty when
    /// padding leaves nothing, such as for a silence shorter than the two pads.
    public func timeRange(for range: ItemRange) throws(EditError) -> TimeRange {
        let indices = try indices(of: range)
        let start = boundary(before: indices.lowerBound)
        let end = boundary(before: indices.upperBound + 1)
        return TimeRange(start: start, end: max(start, end))
    }
}

import AppKit
import ProjectKit

/// The transcript as text for the inspector's text view: what each run of characters is, so a selection
/// maps back to words and silences, and where the rail's marks go (docs/ui.md, "The transcript in the
/// inspector").
struct TranscriptDocument {
    /// One word or silence in the text.
    struct Piece {
        let token: TranscriptReading.Token
        let range: NSRange
        /// A long silence, a block of its own.
        let isBlock: Bool
    }

    /// A paragraph's rail: the app in front where it starts, and where another window came to the front.
    struct Rail {
        let range: NSRange
        let front: ScreenFront?
        let ticks: [(location: Int, front: ScreenFront, time: TimeInterval?)]
        /// Where the paragraph starts playing, for clicking its icon.
        let time: TimeInterval?
    }

    /// How far the text sits from the left, leaving room for the rail.
    static let railWidth: CGFloat = 26
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
    static let chipFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)

    let text: NSAttributedString
    let pieces: [Piece]
    let rails: [Rail]
    /// The text standing in for a fix while it's timed.
    let pendingRanges: [NSRange]

    init(reading: TranscriptReading?, pending: TranscriptFixing.Request?, transcripts: TranscriptIndex) {
        let text = NSMutableAttributedString()
        var pieces: [Piece] = []
        var rails: [Rail] = []
        var pendingRanges: [NSRange] = []
        var pendingClips: Set<ClipID?> = []

        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = Self.railWidth
        paragraph.headIndent = Self.railWidth
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 12
        let base: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let blockStyle = (paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? paragraph
        blockStyle.alignment = .center
        blockStyle.paragraphSpacingBefore = 2

        // Use exact ids: cut-point padding is for editing footage, not for replacing displayed text.
        var pendingWords: Set<TranscriptItemID> = []
        if let pending, let transcript = try? transcripts.transcript(containing: pending.range),
           let indices = try? CutPointSnapper(transcript: transcript).indices(of: pending.range) {
            pendingWords = Set(transcript.items[indices].filter { !$0.isSilence }.map(\.id))
        }
        func isPending(_ token: TranscriptReading.Token) -> Bool {
            pendingWords.contains(token.item)
        }

        for block in reading?.blocks ?? [] {
            if text.length > 0 { text.append(NSAttributedString(string: "\n", attributes: base)) }
            switch block {
            case .silence(let token):
                let length = token.silenceLength ?? 0
                var attributes = base
                attributes[.paragraphStyle] = blockStyle
                attributes[.font] = Self.chipFont
                attributes[.foregroundColor] = token.isCut ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor
                if token.isCut { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                let start = text.length
                text.append(NSAttributedString(string: "\(Self.seconds(length)) of silence", attributes: attributes))
                pieces.append(Piece(token: token, range: NSRange(location: start, length: text.length - start), isBlock: true))
            case .paragraph(let words):
                let start = text.length
                var ticks: [(Int, ScreenFront, TimeInterval?)] = []
                for (index, token) in words.tokens.enumerated() {
                    if isPending(token) {
                        // The fix shows at once in place of the words it replaces, while it's timed.
                        guard pendingClips.insert(token.id.clip).inserted, let pending else { continue }
                        if text.length > start { text.append(NSAttributedString(string: " ", attributes: base)) }
                        var attributes = base
                        attributes[.foregroundColor] = NSColor.secondaryLabelColor
                        let location = text.length
                        text.append(NSAttributedString(string: pending.text, attributes: attributes))
                        pendingRanges.append(NSRange(location: location, length: text.length - location))
                        continue
                    }
                    if index > 0 { text.append(NSAttributedString(string: " ", attributes: base)) }
                    let location = text.length
                    var attributes = base
                    switch token.kind {
                    case .word(let word):
                        if token.isCut {
                            attributes[.foregroundColor] = NSColor.tertiaryLabelColor
                            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                        }
                        if token.isUntimed {
                            attributes[.toolTip] = "These words cut as one."
                        }
                        text.append(NSAttributedString(string: word.isEmpty ? "·" : word, attributes: attributes))
                    case .silence(let length):
                        attributes[.font] = Self.chipFont
                        attributes[.foregroundColor] = token.isCut ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor
                        if token.isCut { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                        // Thin spaces give the chip's background room either side of its digits.
                        text.append(NSAttributedString(string: "\u{2009}\(Self.seconds(length))\u{2009}", attributes: attributes))
                    }
                    let range = NSRange(location: location, length: text.length - location)
                    pieces.append(Piece(token: token, range: range, isBlock: false))
                    if let change = token.windowChange { ticks.append((location, change, token.timeline?.start)) }
                }
                let first = words.tokens.first { !$0.isCut }?.timeline?.start
                rails.append(Rail(range: NSRange(location: start, length: text.length - start), front: words.front, ticks: ticks, time: first))
            }
        }
        self.text = text
        self.pieces = pieces
        self.rails = rails
        self.pendingRanges = pendingRanges
    }

    /// "1.4 s", or "1:05" from a minute up.
    static func seconds(_ length: TimeInterval) -> String {
        length < 60 ? String(format: "%.1f s", length) : String(format: "%d:%02d", Int(length) / 60, Int(length) % 60)
    }

    /// The pieces a selection touches, rounded out to whole words.
    func pieces(in selection: NSRange) -> [Piece] {
        if selection.length == 0 { return [] }
        return pieces.filter { NSIntersectionRange($0.range, selection).length > 0 }
    }

    /// The piece holding a character, if any.
    func piece(at location: Int) -> Piece? {
        pieces.first { NSLocationInRange(location, $0.range) }
    }

    /// The word before a caret, and the word after it.
    func word(before location: Int) -> Piece? {
        pieces.last { $0.token.text != nil && $0.range.location < location }
    }

    func word(after location: Int) -> Piece? {
        pieces.first { $0.token.text != nil && $0.range.upperBound > location }
    }

    /// The piece playing at a time on the timeline.
    func piece(playingAt time: TimeInterval) -> Piece? {
        pieces.first { piece in piece.token.timeline.map { $0.start <= time && time < $0.end } ?? false }
    }

    /// Where a token is now, by its id.
    func range(of id: TranscriptReading.Token.ID) -> NSRange? {
        pieces.first { $0.token.id == id }?.range
    }
}

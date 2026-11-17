import Foundation
import Testing
@testable import ProjectKit

/// Captions' maths: pages, motion, lines, onsets and the style as data (docs/decisions.md, 80).
@Suite struct CaptionPagesTests {
    let style = CaptionStyle.pop(for: .landscape)

    func word(_ number: Int, _ text: String, _ start: TimeInterval, _ end: TimeInterval, clip: Int = 1, startsLine: Bool = false) -> CaptionWord {
        CaptionWord(id: WordID(number: number), text: text, timeline: TimeRange(start: start, end: end), clip: ClipID(number: clip), startsLine: startsLine)
    }

    func texts(_ pages: [CaptionPage]) -> [[String]] { pages.map { $0.words.map(\.text) } }

    @Test func aSentenceEndAClauseAndAPauseEachStartAPage() {
        let words = [
            word(1, "Hello", 0, 0.3), word(2, "there.", 0.3, 0.6),
            word(3, "So,", 0.6, 0.8), word(4, "well,", 0.8, 1.0), word(5, "this", 1.0, 1.2),
            word(6, "runs", 1.2, 1.4), word(7, "on", 1.8, 2.0),
        ]
        // "So," alone doesn't break: a clause needs two words first.
        #expect(texts(CaptionPaginator.pages(words, style: style)) == [["Hello", "there."], ["So,", "well,"], ["this", "runs"], ["on"]])
    }

    @Test func noPunctuationStillBreaksAtPausesAndTheWordLimit() {
        // As on one of real takes: all lowercase, no punctuation at all.
        let words = (0..<9).map { index in word(index + 1, "word", Double(index) * 0.3, Double(index) * 0.3 + 0.25) }
            + [word(10, "after", 3.5, 3.8)]
        let pages = CaptionPaginator.pages(words, style: style)
        #expect(pages.map(\.words.count) == [4, 4, 1, 1])
    }

    @Test func theCharacterLimitAndACutBreakAPage() {
        let long = [word(1, "extraordinarily", 0, 0.5), word(2, "complicated", 0.5, 1.0), word(3, "words", 1.0, 1.2)]
        // 15 + 1 + 11 characters fits the 30; adding "words" doesn't.
        #expect(texts(CaptionPaginator.pages(long, style: style)) == [["extraordinarily", "complicated"], ["words"]])
        let cut = [word(1, "one", 0, 0.2), word(2, "two", 0.2, 0.4, clip: 2)]
        #expect(CaptionPaginator.pages(cut, style: style).count == 2)
    }

    @Test func aForcedBreakPastTheLinesStartsAPage() {
        var short = style
        short.words.lines = 1
        let words = [word(1, "one", 0, 0.2), word(2, "two", 0.2, 0.4, startsLine: true), word(3, "three", 0.4, 0.6)]
        #expect(texts(CaptionPaginator.pages(words, style: short)) == [["one"], ["two", "three"]])
        // With two lines, the break stays inside the page.
        let pages = CaptionPaginator.pages(words, style: style)
        #expect(pages.count == 1 && pages[0].words[1].startsLine && !pages[0].words[0].startsLine)
    }

    @Test func aPageHoldsBridgesAndNeverOutlastsItsClip() {
        let words = [word(1, "one.", 0, 0.5), word(2, "two.", 0.7, 1.0), word(3, "three.", 3.0, 3.2)]
        let pages = CaptionPaginator.pages(words, style: style, clipEnds: [ClipID(number: 1): 3.3])
        // A 0.2 s gap is bridged; a long one gets the hold; the last ends with its clip.
        #expect(pages[0].show.end == 0.7)
        #expect(abs(pages[1].show.end - (1.0 + CaptionPaginator.hold)) < 1e-9)
        #expect(pages[2].show.end == 3.3)
    }

    @Test func theSpokenWordHoldsUntilTheNextStarts() {
        let page = CaptionPage(words: [word(1, "a", 1, 1.2), word(2, "b", 1.5, 1.7)], show: TimeRange(start: 1, end: 2.1))
        #expect(page.spokenIndex(at: 0.9) == nil)
        #expect(page.spokenIndex(at: 1.3) == 0, "Between words, the last one stays marked.")
        #expect(page.spokenIndex(at: 1.5) == 1)
        #expect(page.turn(of: 0) == TimeRange(start: 1, end: 1.5))
        #expect(page.turn(of: 1) == TimeRange(start: 1.5, end: 2.1))
    }

    @Test func displayTextDropsCommasAndStopsButKeepsQuestions() {
        #expect(CaptionPaginator.displayText(" really, ", style: style) == "REALLY")
        #expect(CaptionPaginator.displayText("new?", style: style) == "NEW?")
        var keeping = style
        keeping.words.keepsPunctuation = true
        keeping.words.uppercase = false
        #expect(CaptionPaginator.displayText("there.", style: keeping) == "there.")
    }

    /// Captions come from the played words: fillers out, a fix's words in, cut words gone, times on the
    /// timeline through speed.
    @Test func wordsFollowCutsFixesAndSpeed() throws {
        let transcript = TranscriptDraft(engine: "test", silenceDetector: "test", language: "en", audioDuration: 6, items: [
            .word(.init(text: "Hello", start: 1.0, end: 1.4)), .word(.init(text: "there.", start: 1.45, end: 1.8)),
            .silence(start: 1.8, end: 2.6),
            .word(.init(text: "Um,", start: 2.6, end: 2.9, isFiller: true)),
            .silence(start: 2.9, end: 3.0),
            .word(.init(text: "this", start: 3.0, end: 3.3)), .word(.init(text: "is", start: 3.3, end: 3.5)),
            .word(.init(text: "the", start: 3.5, end: 3.7)), .word(.init(text: "take.", start: 3.7, end: 4.1)),
        ]).assigningIDs(source: SourceID(number: 1), firstWordNumber: 1, firstSilenceNumber: 1).transcript
        var edit = Edit(main: [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0.9, sourceOut: 4.2)])
        edit.setCaptions(true)
        var next = 100
        try edit.fixWords(ItemRange(first: .word(WordID(number: 4)), last: .word(WordID(number: 4))), as: "these",
                          timings: [AlignedWord(text: "these", start: 3.0, end: 3.3)], transcripts: TranscriptIndex([transcript]), nextWordNumber: &next)
        edit.captions.setEmphasis([WordID(number: 100)], on: true)
        let fixed = TranscriptIndex([transcript], fixes: edit.fixes)
        let words = CaptionPaginator.words(edit: edit, output: .landscape, placements: edit.placements, transcripts: fixed)
        #expect(words.map(\.text) == ["Hello", "there.", "these", "is", "the", "take."])
        #expect(words[2].id == WordID(number: 100) && words[2].isEmphasised)
        #expect(abs(words[0].timeline.start - 0.1) < 1e-9)

        // Cut "there." and the pause: the rest moves up.
        edit.main = [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0.9, sourceOut: 1.42),
                     Clip(id: ClipID(number: 2), source: SourceID(number: 1), sourceIn: 2.95, sourceOut: 4.2)]
        edit.setCaptions(true)
        _ = try edit.setSpeed(ClipSpeed(rate: 2) ?? .normal, for: ClipID(number: 2))
        let cut = CaptionPaginator.words(edit: edit, output: .landscape, placements: edit.placements, transcripts: fixed, lead: 0.05)
        #expect(cut.map(\.text) == ["Hello", "these", "is", "the", "take."])
        // The lead would put "these" before its clip starts: it stops at the cut instead.
        #expect(abs(cut[1].timeline.start - 0.52) < 1e-9)

        // Only the clips that show captions give words: turn the second clip's off.
        edit.setCaptions(false, for: [ClipID(number: 2)])
        #expect(CaptionPaginator.words(edit: edit, output: .landscape, placements: edit.placements, transcripts: fixed).map(\.text) == ["Hello"])
        // A clip shows captions or it doesn't, in both shapes alike.
        #expect(CaptionPaginator.words(edit: edit, output: .vertical, placements: edit.placements, transcripts: fixed).map(\.text) == ["Hello"])
    }

    /// The rule: the same as the inset's (docs/decisions.md, 68). A split copies it into both pieces; a clip
    /// added later takes the one before's; it doesn't carry into the next take.
    @Test func captionsFollowTheClipLikeItsInset() throws {
        let transcript = TranscriptDraft(engine: "test", silenceDetector: "test", language: "en", audioDuration: 4, items: [
            .word(.init(text: "one", start: 0.5, end: 0.9)), .silence(start: 0.9, end: 1.5), .word(.init(text: "two", start: 1.5, end: 1.9)),
        ]).assigningIDs(source: SourceID(number: 1), firstWordNumber: 1, firstSilenceNumber: 1).transcript
        var edit = Edit(main: [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 4)])
        edit.setCaptions(true)
        _ = try edit.split(at: 1.2)
        _ = transcript
        #expect(edit.main.count == 2)
        #expect(edit.main.allSatisfy { $0.look.captions })
        #expect(edit.prevailingLook?.clip.captions == false)
    }

    @Test(arguments: [0.5, -0.5])
    func aLeadCannotMoveWordsIntoAnAdjacentClip(lead: Double) {
        let source = SourceID(number: 1)
        let transcript = TranscriptDraft(engine: "test", silenceDetector: "test", language: "en", audioDuration: 3,
            items: [.word(.init(text: "start", start: 1, end: 1.3)), .word(.init(text: "end", start: 1.7, end: 2))])
            .assigningIDs(source: source, firstWordNumber: 1, firstSilenceNumber: 1).transcript
        var edit = Edit(main: (0..<3).map { Clip(id: ClipID(number: $0 + 1), source: source, sourceIn: Double($0), sourceOut: Double($0 + 1)) })
        edit.setCaptions(true, for: [ClipID(number: 2)])
        let words = CaptionPaginator.words(edit: edit, output: .landscape, placements: edit.placements,
                                           transcripts: TranscriptIndex([transcript]), lead: lead)
        #expect(!words.isEmpty)
        #expect(words.allSatisfy { $0.timeline.start >= 1 && $0.timeline.end <= 2 && !$0.timeline.isEmpty })
        let pages = CaptionPaginator.pages(words, style: style, clipEnds: [ClipID(number: 2): 2])
        #expect(pages.allSatisfy { $0.show.start >= 1 && $0.show.end <= 2 })
    }
}

@Suite struct CaptionMotionTests {
    let spring = CaptionStyle.Spring(period: 0.3, damping: 0.6)

    @Test func theSpringStartsAtZeroOvershootsOnceAndSettles() {
        #expect(CaptionMotion.spring(0, spring) == 0)
        #expect(CaptionMotion.spring(-1, spring) == 0)
        let samples = stride(from: 0.0, through: 1.5, by: 0.001).map { CaptionMotion.spring($0, spring) }
        let peak = samples.max() ?? 0
        #expect(abs(peak - 1 - CaptionMotion.overshoot(damping: 0.6)) < 0.002, "The overshoot formula matches the spring's own peak.")
        #expect(abs(CaptionMotion.spring(1.5, spring) - 1) < 0.001)
    }

    @Test func easingRunsFromZeroToOne() {
        #expect(CaptionMotion.easeOut(-0.1, over: 0.2) == 0)
        #expect(CaptionMotion.easeOut(0.2, over: 0.2) == 1)
        #expect(CaptionMotion.easeOut(0.1, over: 0.2) > 0.5, "Eases out: past halfway by half time.")
        #expect(CaptionMotion.easeInOut(0.05, over: 0.1) == 0.5)
    }

    @Test func aPagePopsInAndFadesOutAtItsEnd() {
        let style = CaptionStyle.pop(for: .vertical)
        let show = TimeRange(start: 1, end: 2)
        let start = CaptionMotion.page(at: 1, show: show, style: style)
        #expect(start.opacity == 0 && abs(start.scale - CaptionMotion.popFrom) < 1e-9)
        let settled = CaptionMotion.page(at: 1.9, show: show, style: style)
        #expect(settled.opacity == 1 && abs(settled.scale - 1) < 0.01)
        #expect(CaptionMotion.page(at: 1.99, show: show, style: style).opacity < 0.5)
    }

    @Test func theSpokenWordSpringsUpAndBack() {
        let style = CaptionStyle.pop(for: .landscape)
        let words = [CaptionWord(id: WordID(number: 1), text: "a", timeline: TimeRange(start: 0, end: 0.3), clip: ClipID(number: 1)),
                     CaptionWord(id: WordID(number: 2), text: "b", timeline: TimeRange(start: 0.5, end: 0.8), clip: ClipID(number: 1))]
        let page = CaptionPage(words: words, show: TimeRange(start: 0, end: 2))
        #expect(CaptionMotion.word(at: 0, index: 0, of: page, style: style).scale == 1)
        #expect(abs(CaptionMotion.word(at: 0.45, index: 0, of: page, style: style).scale - style.spoken.scale) < 0.01)
        #expect(abs(CaptionMotion.word(at: 1.9, index: 0, of: page, style: style).scale - 1) < 0.01, "Back to rest after its turn.")
        #expect(CaptionMotion.isMarked(0, spoken: 1, reach: .word) == false)
        #expect(CaptionMotion.isMarked(0, spoken: 1, reach: .throughWord))
        #expect(CaptionMotion.isMarked(1, spoken: nil, reach: .word) == false)
    }

    @Test func wordsCanComeInOneByOne() {
        var style = CaptionStyle.pop(for: .landscape)
        style.entrance.reveal = .word
        style.entrance.motion = .fade
        let words = [CaptionWord(id: WordID(number: 1), text: "a", timeline: TimeRange(start: 0, end: 0.3), clip: ClipID(number: 1)),
                     CaptionWord(id: WordID(number: 2), text: "b", timeline: TimeRange(start: 0.5, end: 0.8), clip: ClipID(number: 1))]
        let page = CaptionPage(words: words, show: TimeRange(start: 0, end: 2))
        #expect(CaptionMotion.word(at: 0.3, index: 1, of: page, style: style).opacity == 0)
        #expect(CaptionMotion.word(at: 1, index: 1, of: page, style: style).opacity == 1)
        #expect(CaptionMotion.page(at: 0, show: page.show, style: style).opacity == 1, "The page itself doesn't fade in.")
    }

    @Test func theBoxGlidesOnALineAndJumpsBetweenLines() throws {
        let words = (0..<3).map { CaptionWord(id: WordID(number: $0 + 1), text: "w", timeline: TimeRange(start: Double($0), end: Double($0) + 0.5), clip: ClipID(number: 1)) }
        let page = CaptionPage(words: words, show: TimeRange(start: 0, end: 3))
        let rects = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 20, y: 0, width: 10, height: 10), CGRect(x: 0, y: 30, width: 10, height: 10)]
        #expect(CaptionMotion.box(at: 0.5, page: page, rects: rects) == rects[0])
        let gliding = try #require(CaptionMotion.box(at: 1 + CaptionMotion.boxGlide / 2, page: page, rects: rects))
        #expect(abs(gliding.minX - 10) < 1e-9)
        #expect(CaptionMotion.box(at: 2.01, page: page, rects: rects) == rects[2], "To another line it jumps.")
    }
}

@Suite struct CaptionLinesTests {
    @Test func wrapsGreedilyThenEvensTheLastTwoLines() {
        // Greedy fills 40 10 10 | 40 (70 and 40); moving one word down gives 55 and 55.
        #expect(CaptionLines.wrap(widths: [40, 10, 10, 40], startsLine: [], space: 5, maximumWidth: 70) == [[0, 1], [2, 3]])
        // Two then one is already as even as it gets.
        #expect(CaptionLines.wrap(widths: [30, 30, 30], startsLine: [], space: 5, maximumWidth: 70) == [[0, 1], [2]])
        #expect(CaptionLines.wrap(widths: [30, 30], startsLine: [], space: 5, maximumWidth: 70) == [[0, 1]])
    }

    @Test func aTooWideWordStandsAloneAndAskedBreaksAreKept() {
        #expect(CaptionLines.wrap(widths: [100, 10], startsLine: [], space: 5, maximumWidth: 50) == [[0], [1]])
        #expect(CaptionLines.wrap(widths: [10, 10, 10], startsLine: [false, false, true], space: 5, maximumWidth: 200) == [[0, 1], [2]])
    }
}

@Suite struct CaptionStyleTests {
    @Test(arguments: [
        #"{"lettering":{"lineSpacing":0}}"#, #"{"lettering":{"wordSpacing":-1}}"#,
        #"{"lettering":{"stroke":{"width":-1}}}"#, #"{"lettering":{"shadow":{"blur":-1}}}"#,
        #"{"lettering":{"shadow":{"drop":-1}}}"#, #"{"lettering":{"shadow":{"opacity":2}}}"#,
        ##"{"spoken":{"box":{"color":"#000000","opacity":1,"padding":-1,"corner":0}}}"##,
        ##"{"spoken":{"box":{"color":"#000000","opacity":-1,"padding":0,"corner":0}}}"##,
        ##"{"spoken":{"box":{"color":"#000000","opacity":1,"padding":0,"corner":-1}}}"##,
    ])
    func changesRejectUndrawableGeometryAndOpacity(changes: String) {
        #expect(throws: CaptionStyleError.self) { try CaptionStyle.pop(for: .landscape).changing(with: Data(changes.utf8)) }
    }
    @Test func theCatalogIsValidAndNamed() {
        for output in OutputShape.allCases {
            for style in CaptionStyle.catalog(for: output) { #expect(style.problem == nil) }
            #expect(CaptionStyle.named("pop", for: output)?.name == "Pop")
        }
        #expect(CaptionStyle.named("Karaoke", for: .landscape) == nil)
    }

    @Test func highlightPutsABoxBehindTheWordBeingSaid() throws {
        for output in OutputShape.allCases {
            let style = try #require(CaptionStyle.named("highlight", for: output))
            #expect(style.spoken.reach == .word)
            #expect(style.spoken.box != nil)
            #expect(style.spoken.scale == 1 && style.largestScale == 1, "Nothing grows, so the box always fits its word.")
            let box = try #require(style.spoken.box)
            #expect(2 * box.padding < style.lettering.wordSpacing, "The box stays clear of the words either side.")
        }
        var captions = Captions()
        let chosen = captions.setStyle(named: "Highlight")
        #expect(chosen)
        #expect(captions.styleName == "Highlight")
        #expect(captions[.vertical].style == .highlight(for: .vertical))
    }

    @Test func changesMergeIntoTheStyle() throws {
        let style = CaptionStyle.pop(for: .landscape)
        let changed = try style.changing(with: Data(##"{"spoken": {"fill": "#00FF66", "box": {"color": "#000000", "opacity": 0.8, "padding": 0.1, "corner": 0.2}}, "words": {"atOnce": 2}, "lettering": {"shadow": null}}"##.utf8))
        #expect(changed.spoken.fill == "#00FF66" && changed.spoken.scale == style.spoken.scale)
        #expect(changed.spoken.box?.opacity == 0.8)
        #expect(changed.words.atOnce == 2 && changed.words.characters == style.words.characters)
        #expect(changed.lettering.shadow == nil && changed.lettering.stroke == style.lettering.stroke)
        #expect(throws: CaptionStyleError.self) { try style.changing(with: Data(##"{"lettering": {"fill": "white"}}"##.utf8)) }
        #expect(throws: (any Error).self) { try style.changing(with: Data(##"{"words": {"atOnce": "two"}}"##.utf8)) }
    }

    @Test func theLargestScaleCoversEveryMotion() {
        let style = CaptionStyle.pop(for: .landscape)
        #expect(style.largestScale >= style.emphasis.scale * style.spoken.scale)
    }

    @Test func captionsRoundTripInTheEditAtItsFormat() throws {
        var edit = Edit()
        edit.main = [Clip(id: ClipID(number: 1), source: SourceID(number: 1), sourceIn: 0, sourceOut: 2),
                     Clip(id: ClipID(number: 2), source: SourceID(number: 1), sourceIn: 3, sourceOut: 4)]
        edit.setCaptions(true, for: [ClipID(number: 2)])
        edit.captions.timing.lead = 0.04
        edit.captions.setEmphasis([WordID(number: 9), WordID(number: 3)], on: true)
        edit.captions.setLineBreaks(before: [WordID(number: 5)], on: true)
        edit.captions.setEmphasis([WordID(number: 9)], on: false)
        let data = try JSONEncoder().encode(edit)
        let read = try JSONDecoder().decode(Edit.self, from: data)
        #expect(read == edit)
        #expect(read.formatVersion == Edit.currentFormatVersion)
        #expect(read.captions.emphasis == [WordID(number: 3)] && read.captions.lineBreaks == [WordID(number: 5)])
        #expect(read.main[1].look.captions && !read.main[0].look.captions)
        #expect(read.showsCaptions && read.captions[.vertical].timing.lead == 0.04 && read.captions[.landscape].timing.lead == 0.04)
        // Written only when on.
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.components(separatedBy: "\"captions\":true").count == 2)
    }
}

import CoreGraphics
import CoreImage
import Foundation
import ProjectKit

/// One output's captions over the whole timeline: its pages and the style. Made once per composition and
/// shared by every stretch of it.
final class CaptionTrack: @unchecked Sendable {
    /// Stable for this track's lifetime and never reused by a later composition.
    let id = UUID()
    let pages: [CaptionPage]
    let style: CaptionStyle

    init(pages: [CaptionPage], style: CaptionStyle) {
        self.pages = pages
        self.style = style
    }

    /// The page on screen at a time, with its index. Pages are in order and never overlap.
    func page(at time: TimeInterval) -> (index: Int, page: CaptionPage)? {
        var low = 0, high = pages.count
        while low < high {
            let middle = (low + high) / 2
            if pages[middle].show.start <= time { low = middle + 1 } else { high = middle }
        }
        guard low > 0, time < pages[low - 1].show.end else { return nil }
        return (low - 1, pages[low - 1])
    }

    /// The pages for an edit's output, or nil when its captions are off.
    static func make(_ inputs: RenderInputs, timeline: EditTimeline, output: OutputShape) -> CaptionTrack? {
        let edit = inputs.edit
        let setting = edit.captions[output]
        guard edit.showsCaptions else { return nil }
        let words = CaptionPaginator.words(edit: edit, output: output, placements: timeline.clips, transcripts: inputs.transcripts, spellings: inputs.spellings,
                                           lead: setting.timing.lead)
        let clipEnds = Dictionary(uniqueKeysWithValues: timeline.clips.map { ($0.clip.id, $0.timeline.end) })
        return CaptionTrack(pages: CaptionPaginator.pages(words, style: setting.style, clipEnds: clipEnds), style: setting.style)
    }
}

/// A panel's captions for one stretch of the timeline: the track, and where the text sits in this stretch's
/// layout.
struct PanelCaptions: @unchecked Sendable {
    var track: CaptionTrack
    var area: CaptionPlacement.Area

    /// The size of the style's text in a panel, in pixels.
    static func textSize(_ style: CaptionStyle, panel: CGSize) -> Double {
        (style.lettering.size * Double(min(panel.width, panel.height))).rounded()
    }

    /// Where a stretch's captions go in a frame laid out as `frame`.
    static func make(track: CaptionTrack, frame: FrameLayout) -> PanelCaptions {
        let style = track.style
        let line = textSize(style, panel: frame.size) * style.lettering.lineSpacing
        let area = CaptionPlacement.area(style: style, size: frame.size, screen: frame.placement(.screen)?.frame ?? frame.placement(.video)?.frame,
                                         camera: frame.placement(.camera)?.frame, lineHeight: line)
        return PanelCaptions(track: track, area: area)
    }
}

/// Draws a panel's captions at a moment (docs/decisions.md, 80). Each page is laid out once and each word
/// drawn once; a frame only transforms and composites them. Used from the compositor's queue only.
final class CaptionDrawer {
    /// A word's place on the panel, from its top left, at rest.
    struct PlacedWord: Equatable {
        var text: String
        /// The size it's laid out at, emphasis included.
        var size: Double
        var left: Double
        var baseline: Double
        var advance: Double
    }

    struct PageLayout: Equatable {
        var words: [PlacedWord]
        /// The block's middle, about which the page scales.
        var centre: CGPoint
        var capHeight: Double
    }

    let rasters = CaptionRasters()
    private struct LayoutKey: Hashable {
        let track: UUID
        let page: Int
        let width: CGFloat
        let height: CGFloat
        let area: CaptionPlacement.Area
    }
    private var layouts: [LayoutKey: PageLayout] = [:]
    /// How many pages have been laid out, for the tests.
    private(set) var laidOut = 0

    /// The captions on screen at `time`, in Core Image's coordinates over the whole frame, or nil when none show.
    ///
    /// - Parameters:
    ///   - frameDuration: A word shows from the frame nearest its start, not the first frame after it, so
    ///     it's never up to a whole frame late.
    ///   - panel: The panel's rectangle in the frame, from the top left.
    ///   - frame: The whole frame's size.
    func overlay(_ captions: PanelCaptions, at time: TimeInterval, frameDuration: TimeInterval = 0, panel: CGRect, frame: CGSize) -> CIImage? {
        let time = time + frameDuration / 2
        let style = captions.track.style
        guard let (index, page) = captions.track.page(at: time) else { return nil }
        let pageState = CaptionMotion.page(at: time, show: page.show, style: style)
        guard pageState.opacity > 0.002 else { return nil }
        let layout = self.layout(of: page, index: index, captions: captions, panel: panel.size)
        let baseSize = PanelCaptions.textSize(style, panel: panel.size)
        let spoken = page.spokenIndex(at: time)
        // Words are drawn at the largest they'll be and only ever scaled down, so they stay sharp.
        let oversize = style.largestScale / max(1, style.emphasis.scale)

        func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: panel.minX + point.x, y: frame.height - (panel.minY + point.y)) }
        let centre = flip(layout.centre)
        let pageTransform = CGAffineTransform(translationX: -centre.x, y: -centre.y)
            .concatenating(CGAffineTransform(scaleX: pageState.scale, y: pageState.scale))
            .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y - pageState.drop * baseSize))

        var overlay = CIImage.empty()
        if let box = style.spoken.box, style.spoken.reach != .none {
            let rects = layout.words.map { word in
                let pad = box.padding * word.size
                return CGRect(x: word.left - pad, y: word.baseline - layout.capHeight * word.size / baseSize - pad,
                              width: word.advance + 2 * pad, height: layout.capHeight * word.size / baseSize + 2 * pad)
            }
            if let rect = CaptionMotion.box(at: time, page: page, rects: rects) {
                let flipped = CGRect(x: panel.minX + rect.minX, y: frame.height - (panel.minY + rect.maxY), width: rect.width, height: rect.height)
                let (red, green, blue) = CaptionRasters.components(box.color)
                let generator = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
                    "inputExtent": CIVector(cgRect: flipped),
                    "inputRadius": box.corner * baseSize,
                    "inputColor": CIColor(red: red * box.opacity, green: green * box.opacity, blue: blue * box.opacity, alpha: box.opacity),
                ])
                if let image = generator?.outputImage { overlay = image.transformed(by: pageTransform).composited(over: overlay) }
            }
        }

        for (offset, placed) in layout.words.enumerated() {
            let word = page.words[offset]
            let state = CaptionMotion.word(at: time, index: offset, of: page, style: style)
            guard state.opacity > 0.002 else { continue }
            let marked = CaptionMotion.isMarked(offset, spoken: spoken, reach: style.spoken.reach)
            let fill = (word.isEmphasised ? style.emphasis.fill : nil) ?? (marked ? style.spoken.fill : nil) ?? style.lettering.fill
            guard let raster = rasters.raster(placed.text, style: style, size: placed.size * oversize, fill: fill) else { continue }
            // The word's pivot: the middle of its capitals, on the frame.
            let pivot = flip(CGPoint(x: placed.left + placed.advance / 2, y: placed.baseline - raster.capHeight / oversize / 2 + state.drop * placed.size))
            let rasterPivot = CGPoint(x: raster.textLeft + raster.advance / 2, y: raster.baseline + raster.capHeight / 2)
            let scale = state.scale / oversize
            var picture = raster.picture.transformed(by: CGAffineTransform(translationX: -rasterPivot.x, y: -rasterPivot.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
                .concatenating(pageTransform))
            if state.opacity < 0.998 { picture = Self.fading(picture, to: state.opacity) }
            overlay = picture.composited(over: overlay)
        }
        if pageState.opacity < 0.998 { overlay = Self.fading(overlay, to: pageState.opacity) }
        let bounds = CGRect(x: panel.minX, y: frame.height - panel.maxY, width: panel.width, height: panel.height)
        return overlay.cropped(to: bounds)
    }

    /// A premultiplied picture at a fraction of its opacity.
    static func fading(_ image: CIImage, to opacity: Double) -> CIImage {
        let value = CGFloat(max(0, min(1, opacity)))
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: value, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: value, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: value, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: value),
        ])
    }

    /// Lays out a page in a panel: wraps it into lines no wider than the style allows and the area has, and
    /// places them against the area's anchor. Kept, so each page is laid out once.
    func layout(of page: CaptionPage, index: Int, captions: PanelCaptions, panel: CGSize) -> PageLayout {
        let key = LayoutKey(track: captions.track.id, page: index, width: panel.width, height: panel.height, area: captions.area)
        if let cached = layouts[key] { return cached }
        if layouts.count > 400 { layouts.removeAll() }
        laidOut += 1
        let style = captions.track.style
        let result = Self.layout(of: page, style: style, area: captions.area, panel: panel,
                                 advance: { rasters.advance($0, style: style, size: $1) }, capHeight: rasters.metrics(style: style, size: PanelCaptions.textSize(style, panel: panel)).capHeight)
        layouts[key] = result
        return result
    }

    /// The layout maths on their own: the widths come from `advance`.
    static func layout(of page: CaptionPage, style: CaptionStyle, area: CaptionPlacement.Area, panel: CGSize,
                       advance: (String, Double) -> Double, capHeight: Double) -> PageLayout {
        let size = PanelCaptions.textSize(style, panel: panel)
        let texts = page.words.map { CaptionPaginator.displayText($0.text, style: style) }
        let sizes = page.words.map { size * ($0.isEmphasised ? style.emphasis.scale : 1) }
        let widths = zip(texts, sizes).map { advance($0, $1) }
        // The outline eats into the gap on each side, so the space is the visible gap plus both outlines.
        let space = size * style.lettering.wordSpacing + 2 * (style.lettering.stroke?.width ?? 0) * size
        let maximumWidth = min(style.words.width * Double(panel.width), area.width)
        let lines = CaptionLines.wrap(widths: widths, startsLine: page.words.map(\.startsLine), space: space, maximumWidth: maximumWidth)
        let lineHeight = size * style.lettering.lineSpacing
        let blockHeight = lineHeight * Double(lines.count)
        let top = area.top(of: blockHeight)
        var placed = [PlacedWord](repeating: PlacedWord(text: "", size: 0, left: 0, baseline: 0, advance: 0), count: page.words.count)
        for (row, line) in lines.enumerated() {
            var x = area.midX - CaptionLines.width(of: line, widths: widths, space: space) / 2
            // Capitals centred in their line.
            let baseline = top + Double(row) * lineHeight + lineHeight / 2 + capHeight / 2
            for index in line {
                placed[index] = PlacedWord(text: texts[index], size: sizes[index], left: x, baseline: baseline, advance: widths[index])
                x += widths[index] + space
            }
        }
        return PageLayout(words: placed, centre: CGPoint(x: area.midX, y: top + blockHeight / 2), capHeight: capHeight)
    }
}

/// What the captions say at a moment, in words, for preview_frames to list beside each still.
public enum CaptionReading {
    /// One output's caption pages, or nil when its captions are off.
    public static func pages(_ inputs: RenderInputs, timeline: EditTimeline, output: OutputShape) -> [CaptionPage]? {
        CaptionTrack.make(inputs, timeline: timeline, output: output)?.pages
    }

    /// The page on screen at a time, with the word being said in brackets, such as "HERE [WE] ARE"; nil when
    /// no page shows. Times are as the compositor reads them, a word showing from its nearest frame.
    public static func text(at time: TimeInterval, pages: [CaptionPage], style: CaptionStyle, frameDuration: TimeInterval) -> String? {
        let track = CaptionTrack(pages: pages, style: style)
        let time = time + frameDuration / 2
        guard let (_, page) = track.page(at: time) else { return nil }
        let spoken = page.spokenIndex(at: time)
        return page.words.enumerated().map { index, word in
            let text = CaptionPaginator.displayText(word.text, style: style)
            return CaptionMotion.isMarked(index, spoken: spoken, reach: .word) && style.spoken.reach != .none ? "[\(text)]" : text
        }.joined(separator: " ")
    }
}

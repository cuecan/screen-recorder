import AVFoundation
import CoreImage
import Foundation
import Testing
import ProjectKit
@testable import RenderKit

/// Where captions sit, from every preset's real geometry (docs/decisions.md, 80).
@Suite struct CaptionPlacementTests {
    let camera = CGSize(width: 1920, height: 1080)

    func frames(_ take: TakeLayout, for destination: VideoFormat.Destination = .both, output: OutputShape) -> FrameLayout {
        let screen = CGSize(width: 1800 * take.captureRatio(for: destination).aspect, height: 1800)
        let pictures = ClipPictures(screen: screen, camera: camera, recordedLayout: take, screenPointHeight: 900)
        let layout = take.layout
        return LayoutGeometry.frame(for: layout, in: output, pictures: pictures, look: OutputLook(inset: .medium))
    }

    func area(_ frame: FrameLayout, style: CaptionStyle) -> CaptionPlacement.Area {
        PanelCaptions.make(track: CaptionTrack(pages: [], style: style), frame: frame).area
    }

    /// Every preset of every format, in each output it makes: the text stays inside the frame and its edge
    /// margins, and, except where it straddles a stacked seam on purpose, off the camera.
    @Test func everyPresetKeepsTheTextInsideTheFrameAndOffTheCamera() {
        for destination in VideoFormat.Destination.allCases {
            let outputs: [OutputShape] = destination == .both ? [.landscape, .vertical] : [destination == .landscape ? .landscape : .vertical]
            for preset in takeLayouts(for: destination) {
                for output in outputs {
                    let frame = frames(preset, for: destination, output: output)
                    let style = CaptionStyle.pop(for: output)
                    let found = area(frame, style: style)
                    let size = PanelCaptions.textSize(style, panel: frame.size)
                    let lineHeight = size * style.lettering.lineSpacing
                    let block = 2 * lineHeight
                    let top = found.top(of: block)
                    let label = "\(preset) in \(output): \(found)"
                    #expect(found.left >= 0 && found.right <= Double(frame.size.width) && found.width > 0, "\(label)")
                    #expect(top >= Double(frame.size.height) * CaptionPlacement.edgeMargin - 1, "\(label)")
                    #expect(top + block <= Double(frame.size.height) * (1 - CaptionPlacement.edgeMargin) + 1, "\(label)")
                    guard found.reason != .seam || found.alignment != .centre, let cameraRect = frame.placement(.camera)?.frame else { continue }
                    // One line, as wide as the area allows, centred: it mustn't touch the camera.
                    let width = min(found.width, style.words.width * Double(frame.size.width))
                    let line = CGRect(x: found.midX - width / 2, y: found.alignment == .bottom ? found.anchor - lineHeight : found.top(of: lineHeight),
                                      width: width, height: lineHeight)
                    #expect(!line.insetBy(dx: 1, dy: 1).intersects(cameraRect), "\(label) camera \(cameraRect)")
                }
            }
        }
    }

    @Test func aShortsSplitPutsTheTextOnTheSeam() throws {
        let frame = frames(.sideBySide(.nineByEight), output: .vertical)
        let found = area(frame, style: .pop(for: .vertical))
        let screen = try #require(frame.placement(.screen)?.frame), cameraRect = try #require(frame.placement(.camera)?.frame)
        #expect(found.reason == .seam)
        #expect(abs(found.anchor - (min(screen.maxY, cameraRect.maxY) + max(screen.minY, cameraRect.minY)) / 2) < Double(frame.size.height) / 2)
        let upper = screen.midY < cameraRect.midY ? screen : cameraRect
        let lower = screen.midY < cameraRect.midY ? cameraRect : screen
        #expect(found.anchor >= Double(upper.maxY) && found.anchor <= Double(lower.minY))
    }

    @Test func aVideosCardKeepsTheTextLowAndBesideTheCard() throws {
        let frame = frames(.card(Card(position: .bottomRight)), for: .landscape, output: .landscape)
        let found = area(frame, style: .pop(for: .landscape))
        let cameraRect = try #require(frame.placement(.camera)?.frame)
        #expect(found.reason == .low)
        #expect(found.alignment == .bottom)
        #expect(found.right <= Double(cameraRect.minX) + 0.5 || found.left >= Double(cameraRect.maxX) - 0.5)
    }

    @Test func freeBandsAndAskedPositions() {
        #expect(CaptionPlacement.freeBands(height: 100, pictures: [CGRect(x: 0, y: 10, width: 10, height: 30), CGRect(x: 0, y: 30, width: 10, height: 20)])
                == [0...10, 50...100])
        let wide = CaptionPlacement.area(style: .pop(for: .landscape), size: CGSize(width: 1920, height: 1080),
                                         screen: CGRect(x: 0, y: 0, width: 1920, height: 600), camera: nil, lineHeight: 80)
        #expect(wide.reason == .freeBand && wide.alignment == .centre)
        var top = CaptionStyle.pop(for: .landscape)
        top.position = .top
        top.offset = 0.05
        let asked = CaptionPlacement.area(style: top, size: CGSize(width: 1920, height: 1080), screen: nil, camera: nil, lineHeight: 80)
        #expect(asked.reason == .asked && abs(asked.anchor - 1080 * (CaptionPlacement.edgeMargin + 0.05)) < 1e-9)
    }
}

/// Laying a page out, with made-up widths.
@Suite struct CaptionLayoutTests {
    @Test func cachedLayoutsIncludeAlignmentAndExactPanelSize() {
        let page = CaptionPage(words: [CaptionWord(id: WordID(number: 1), text: "one", timeline: TimeRange(start: 0, end: 1), clip: ClipID(number: 1))],
                               show: TimeRange(start: 0, end: 1))
        let track = CaptionTrack(pages: [page], style: .pop(for: .landscape))
        var captions = PanelCaptions(track: track, area: .init(left: 0, right: 1000, anchor: 500, alignment: .bottom, reason: .low))
        let drawer = CaptionDrawer()
        let bottom = drawer.layout(of: page, index: 0, captions: captions, panel: CGSize(width: 1920, height: 1080.1))
        captions.area.alignment = .top
        let top = drawer.layout(of: page, index: 0, captions: captions, panel: CGSize(width: 1920, height: 1080.1))
        #expect(top.centre.y > bottom.centre.y)
        _ = drawer.layout(of: page, index: 0, captions: captions, panel: CGSize(width: 1920, height: 1080.9))
        #expect(drawer.laidOut == 3)
        _ = drawer.layout(of: page, index: 0, captions: captions, panel: CGSize(width: 1920, height: 1080.9))
        #expect(drawer.laidOut == 3)
    }
    @Test func linesAreCentredInTheAreaAndBelowEachOther() {
        let style = CaptionStyle.pop(for: .landscape)
        let words = ["one", "two", "three"].enumerated().map { index, text in
            CaptionWord(id: WordID(number: index + 1), text: text, timeline: TimeRange(start: Double(index), end: Double(index) + 0.5), clip: ClipID(number: 1))
        }
        let page = CaptionPage(words: words, show: TimeRange(start: 0, end: 3))
        let area = CaptionPlacement.Area(left: 100, right: 700, anchor: 900, alignment: .bottom, reason: .low)
        // Every word 250 wide: two can't share a 600 line with the outline and gap between them... one can.
        let layout = CaptionDrawer.layout(of: page, style: style, area: area, panel: CGSize(width: 1920, height: 1080),
                                          advance: { _, _ in 250 }, capHeight: 50)
        let size = PanelCaptions.textSize(style, panel: CGSize(width: 1920, height: 1080))
        let space = size * style.lettering.wordSpacing + 2 * (style.lettering.stroke?.width ?? 0) * size
        #expect(layout.words.map(\.text) == ["ONE", "TWO", "THREE"])
        // 250 + space + 250 fits in 600: "ONE TWO" share the first line, "THREE" is alone on the second.
        #expect(layout.words[0].baseline == layout.words[1].baseline)
        #expect(layout.words[2].baseline > layout.words[1].baseline)
        #expect(abs(layout.words[0].left - (400 - (500 + space) / 2)) < 1e-9, "Centred in the area.")
        #expect(abs(layout.words[1].left - (layout.words[0].left + 250 + space)) < 1e-9)
        #expect(abs(layout.words[2].left - (400 - 125)) < 1e-9)
        // The block's bottom sits on the anchor.
        #expect(abs(layout.centre.y - (900 - size * style.lettering.lineSpacing)) < 1e-9)
    }
}

/// Captions through the whole composition, on synthetic files: in stills, through a cut and a fix.
@Suite(.serialized) struct CaptionCompositionTests {
    let folder: ProjectFolder

    init() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cuecan-captions-\(UUID().uuidString)")
        folder = try ProjectFolder.create(at: url, title: "Caption test")
        let recordings = folder.url(for: .recordings)
        // A dark screen, so white and yellow text stands out.
        let dark = SyntheticMedia.Color(red: 20, green: 20, blue: 60)
        try await SyntheticMedia.writeVideo(dark, width: 640, height: 540, seconds: 6, to: recordings.appending(path: "screen.mov"))
        try await SyntheticMedia.writeVideo(SyntheticMedia.blue, width: 320, height: 180, seconds: 6, to: recordings.appending(path: "camera.mov"))
        try SyntheticMedia.writeTone(seconds: 6, to: recordings.appending(path: "mic.wav"))
        try folder.updateProject { project in
            project.addSource(
                name: "Screen recording", origin: .recorded,
                tracks: [
                    SourceTrack(kind: .screen, file: .inProject("recordings/screen.mov"), media: MediaInfo(duration: 6, video: .init(width: 640, height: 540, frameRate: 30, captureRate: 30, codec: "avc1"))),
                    SourceTrack(kind: .camera, file: .inProject("recordings/camera.mov"), media: MediaInfo(duration: 6, video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1"))),
                    SourceTrack(kind: .microphone, file: .inProject("recordings/mic.wav"), media: MediaInfo(duration: 6, audio: .init(sampleRate: 48_000, channels: 1, codec: "lpcm"))),
                ],
                captureArea: CaptureArea(ratio: .thirtyTwoByTwentySeven, heightPoints: 270),
                layout: .sideBySide(.thirtyTwoByTwentySeven)
            )
        }
        _ = try folder.addTranscript(speech.draft, for: SourceID(number: 1))
        try folder.updateEdit(author: .system("Test"), reason: "Captions on") { edit in
            edit.main = [clip(1, 0.95, 4.2)]
            edit.setCaptions(true)
            edit.setCaptions(true)
        }
    }

    /// How many pixels in a region are bright and unsaturated (white text) or yellow (the spoken word).
    static func count(_ jpeg: Data, in region: CGRect) throws -> (white: Int, yellow: Int) {
        let pixels = try #require(SyntheticMedia.Pixels(jpeg))
        var white = 0, yellow = 0
        for y in stride(from: Int(region.minY), to: Int(region.maxY), by: 2) {
            for x in stride(from: Int(region.minX), to: Int(region.maxX), by: 2) {
                guard let pixel = pixels[x, y] else { continue }
                if pixel.red > 220, pixel.green > 220, pixel.blue > 220 { white += 1 }
                if pixel.red > 200, pixel.green > 170, pixel.blue < 90 { yellow += 1 }
            }
        }
        return (white, yellow)
    }

    @Test func captionsShowInStillsWithTheSpokenWordMarked() async throws {
        let inputs = try RenderInputs.load(folder)
        let built = try await CompositionBuilder.build(inputs, output: .landscape)
        // "Hello" starts at 0.05 s; at 0.3 s the page has popped in and "HELLO" is being said. Before 0.05 nothing.
        let stills = try await FrameGrabber.stills(of: built, at: [0.0, 0.3, 1.6], maximumWidth: 960)
        let lower = CGRect(x: 0, y: 270, width: 960, height: 270)
        let before = try Self.count(stills[0].jpeg, in: lower)
        let during = try Self.count(stills[1].jpeg, in: lower)
        #expect(before.white == 0 && before.yellow == 0)
        #expect(during.yellow > 20, "The spoken word is yellow: \(during)")
        #expect(during.white > 20, "The rest is white: \(during)")
        // In the pause after "there." the page has gone.
        let pause = try Self.count(stills[2].jpeg, in: lower)
        #expect(pause.yellow == 0)

        let pages = try #require(CaptionReading.pages(inputs, timeline: built.timeline, output: .landscape))
        #expect(pages.map { $0.words.map(\.text) } == [["Hello", "there."], ["this", "is", "the", "take."]])
        #expect(CaptionReading.text(at: 0.3, pages: pages, style: inputs.edit.captions[.landscape].style, frameDuration: 1.0 / 30) == "[HELLO] THERE")
    }

    @Test func aCutAndAFixMoveTheCaptions() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Cut and fix") { edit, transcripts in
            // Cut "Hello there." away, and fix "the take." to "a retake.".
            edit.main = [clip(1, 2.95, 4.2)]
            edit.setCaptions(true)
            var next = 500
            try edit.fixWords(ItemRange(first: w(6), last: w(7)), as: "a retake.", timings: nil, transcripts: transcripts, nextWordNumber: &next)
        }
        let inputs = try RenderInputs.load(folder)
        let built = try await CompositionBuilder.build(inputs, output: .vertical)
        let pages = try #require(CaptionReading.pages(inputs, timeline: built.timeline, output: .vertical))
        #expect(pages.flatMap { $0.words.map(\.text) } == ["this", "is", "a retake."])
        #expect(abs(pages[0].words[0].timeline.start - 0.05) < 1e-6, "The cut moved \"this\" to the start.")
        let still = try #require(try await FrameGrabber.stills(of: built, at: [0.2], maximumWidth: 540).first)
        let counted = try Self.count(still.jpeg, in: CGRect(x: 0, y: 0, width: 540, height: 960))
        #expect(counted.yellow > 20 && counted.white > 20, "\(counted)")
    }

    @Test func captionsOffDrawNothingAndBuildNoTrack() async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Off") { $0.setCaptions(false) }
        let inputs = try RenderInputs.load(folder)
        let built = try await CompositionBuilder.build(inputs, output: .landscape)
        #expect(CaptionReading.pages(inputs, timeline: built.timeline, output: .landscape) == nil)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [0.3], maximumWidth: 960).first)
        let counted = try Self.count(still.jpeg, in: CGRect(x: 0, y: 270, width: 960, height: 270))
        #expect(counted.yellow == 0)
    }

    @Test(arguments: [0.5, -0.5])
    func captionsWithALeadNeverDrawInAnAdjacentDisabledClip(lead: Double) async throws {
        try folder.updateEdit(author: .system("Test"), reason: "Captions on one clip") { edit in
            edit.main = [clip(1, 0.95, 1.9), clip(2, 2.95, 4.2)]
            edit.setCaptions(false)
            edit.setCaptions(true, for: [ClipID(number: lead > 0 ? 2 : 1)])
            edit.captions.timing.lead = lead
        }
        let inputs = try RenderInputs.load(folder)
        let built = try await CompositionBuilder.build(inputs, output: .landscape, scale: 0.5)
        let time = lead > 0 ? 0.7 : 1.1
        let pages = try #require(CaptionReading.pages(inputs, timeline: built.timeline, output: .landscape))
        #expect(!pages.isEmpty)
        #expect(CaptionReading.text(at: time, pages: pages, style: inputs.edit.captions[.landscape].style, frameDuration: 1.0 / 30) == nil)
        let still = try #require(try await FrameGrabber.stills(of: built, at: [time], maximumWidth: 960).first)
        let counted = try Self.count(still.jpeg, in: CGRect(x: 0, y: 0, width: 960, height: 540))
        #expect(counted.white == 0 && counted.yellow == 0)
    }

    @Test func wordsAreDrawnOnceAndPagesLaidOutOnce() throws {
        let drawer = CaptionDrawer()
        let style = CaptionStyle.pop(for: .landscape)
        let words = ["one", "two"].enumerated().map { index, text in
            CaptionWord(id: WordID(number: index + 1), text: text, timeline: TimeRange(start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25), clip: ClipID(number: 1))
        }
        let track = CaptionTrack(pages: [CaptionPage(words: words, show: TimeRange(start: 0, end: 1))], style: style)
        let captions = PanelCaptions(track: track, area: CaptionPlacement.Area(left: 0, right: 1920, anchor: 990, alignment: .bottom, reason: .low))
        for frame in 0..<60 {
            _ = drawer.overlay(captions, at: Double(frame) / 60, frameDuration: 1.0 / 60, panel: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                               frame: CGSize(width: 1920, height: 1080))
        }
        #expect(drawer.laidOut == 1)
        // Each word in white and in yellow, once each: four pictures for sixty frames.
        #expect(drawer.rasters.drawn == 4)
    }
}

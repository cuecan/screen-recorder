import AppKit
import ProjectKit
import SwiftUI
import Testing
@testable import CueCan

@MainActor
struct TranscriptInteractionTests {
    @Test func framingAndSoundChangesKeepTheExistingTranscriptDocumentAndSelection() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        let coordinator = TranscriptTextView.Coordinator(model: model)
        let text = view(coordinator)
        let range = try #require(coordinator.document.pieces.first?.range)
        text.setSelectedRange(range)
        let original = coordinator.document.text
        let reading = model.reading
        let version = model.readingVersion
        let id = try #require(model.edit?.main.first?.id)
        try folder.updateEdit(author: .app, reason: "QA unrelated inspector settings") {
            try $0.setTransform(.init(zoom: 2), picture: .camera, for: [id])
            try $0.setSound(.init(voiceLevel: -12), for: [id])
        }
        model.loadForPreview()
        coordinator.update(version: model.readingVersion, time: 0, playing: false)
        #expect(model.reading == reading)
        #expect(model.readingVersion == version, "Inspector changes that leave words and timings alone must not invalidate the text layout.")
        #expect(coordinator.document.text === original)
        #expect(text.selectedRange() == range)
        try folder.updateEdit(author: .app, reason: "QA real transcript change") {
            _ = try $0.cut(timeline: .init(start: 0, end: 0.7), byHand: true)
        }
        model.loadForPreview()
        coordinator.update(version: model.readingVersion, time: 0, playing: false)
        #expect(model.readingVersion > version)
        #expect(!text.string.contains("word0"), "A real transcript change must still rebuild the document.")
    }

    @Test func transcriptStartsWithTheTextSystemItsChipDrawingUses() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview()
        let hosting = NSHostingView(rootView: TranscriptTextView(model: model))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        func transcript(in view: NSView) -> TranscriptNSTextView? {
            if let text = view as? TranscriptNSTextView { return text }
            return view.subviews.lazy.compactMap { transcript(in: $0) }.first
        }
        let text = try #require(transcript(in: hosting))
        #expect(text.string.contains("word0"))
        // Accessing layoutManager while drawing a chip must not switch text systems mid-paint.
        #expect(text.textLayoutManager == nil, "The transcript draws with TextKit 1 and must start there.")
    }

    @Test func followingARepeatedSourceWordDoesNotSelectTheUnrelatedTextBetweenOccurrences() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let source = try #require(try folder.loadProject().sources.first)
        try folder.updateEdit(author: .app, reason: "Repeat fixture") {
            $0.main.append(Clip(id: ClipID(number: 2), source: source.id, sourceIn: 0, sourceOut: 3))
            $0.nextClipNumber = 3
        }
        let model = EditorModel(folder: folder)
        model.loadForPreview(playhead: 4.2)
        let coordinator = TranscriptTextView.Coordinator(model: model)
        let text = view(coordinator)
        coordinator.follow(selection: .words(ItemRange(.word(WordID(number: 2)))))
        let picked = coordinator.document.pieces(in: text.selectedRange())
        #expect(picked.map(\.token.text) == ["word1"])
        #expect(picked.first?.token.id.clip == ClipID(number: 2))
        #expect(model.currentTime == 4.2)
    }

    @Test func followingWordsAcrossASplitPicksThemOnBothSides() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        try folder.updateEdit(author: .app, reason: "Split fixture") { try $0.split(at: 1.75) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(playhead: 0.2)
        let coordinator = TranscriptTextView.Coordinator(model: model)
        let text = view(coordinator)
        coordinator.follow(selection: .words(ItemRange(first: .word(WordID(number: 2)), last: .word(WordID(number: 3)))))
        let picked = coordinator.document.pieces(in: text.selectedRange()).filter { $0.token.text != nil }
        #expect(picked.map(\.token.text) == ["word1", "word2"])
        #expect(Set(picked.compactMap(\.token.id.clip)).count == 2, "The pick runs across both halves of the split.")
    }

    @Test func correctionFieldPaintsOverTheOriginalTextEvenWithoutAnAppKitBackground() throws {
        let field = TranscriptFixField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 160, height: 80)
        field.isBezeled = false
        field.drawsBackground = false
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.magenta.setFill()
        let oversizedDamage = NSRect(x: 0, y: 0, width: 320, height: 160)
        oversizedDamage.fill()
        field.draw(oversizedDamage)
        context.flushGraphics()
        // Bitmap rows run from the top; the drawing context's origin is at the bottom.
        let pixel = try #require(bitmap.colorAt(x: 80, y: bitmap.pixelsHigh - 40)?.usingColorSpace(.deviceRGB))
        #expect(pixel.alphaComponent == 1)
        #expect(abs(pixel.redComponent - 1) + pixel.greenComponent + abs(pixel.blueComponent - 1) > 0.5,
                "The original magenta backing must be covered by the correction field.")
        let outside = try #require(bitmap.colorAt(x: 240, y: 120)?.usingColorSpace(.deviceRGB))
        #expect(outside.redComponent == 1 && outside.greenComponent == 0 && outside.blueComponent == 1,
                "The field must not paint over the transcript outside its own bounds.")
    }

    @Test func partialTextDeletionCutsTheWholeWordAndFullViewCanPutItBack() throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder)
        model.loadForPreview(playhead: 1.2)
        let coordinator = TranscriptTextView.Coordinator(model: model)
        let text = view(coordinator)
        let first = try #require(coordinator.document.pieces.first)
        text.setSelectedRange(NSRange(location: first.range.location + 1, length: 2))
        coordinator.delete(forward: false)
        let cutDuration = try folder.loadEdit().duration
        #expect(cutDuration < 3)
        #expect(model.currentTime == 1.2, "Programmatic caret placement after cutting must not seek.")
        model.loadForPreview(playhead: 1.2)
        coordinator.update(version: model.readingVersion, time: 1.2, playing: false)
        #expect(!text.string.contains("word0"))
        #expect(text.string.contains("word1"))
        model.transcriptMode = .full
        coordinator.update(version: model.readingVersion, time: 1.2, playing: false)
        let cut = try #require(coordinator.document.pieces.first { $0.token.isCut && $0.token.text == "word0" })
        text.setSelectedRange(cut.range)
        #expect(coordinator.menu().items.contains { $0.title == "Put Back" && $0.isEnabled })
        coordinator.putBack()
        #expect(try folder.loadEdit().duration == 3)
        model.undo()
        #expect(try folder.loadEdit().duration == cutDuration)
    }

    @Test func inlineCorrectionCancelsOnEscapeAndCommitsOnReturn() async throws {
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let model = EditorModel(folder: folder, alignFix: { _, _, _ in nil })
        model.loadForPreview()
        let coordinator = TranscriptTextView.Coordinator(model: model)
        let text = view(coordinator)
        let range = ItemRange(first: .word(WordID(number: 1)), last: .word(WordID(number: 2)))
        coordinator.beginFix(range)
        let cancelled = try #require(text.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(cancelled.isBezeled)
        #expect(text.accessibilityChildren()?.contains { ($0 as? NSTextField) === cancelled } == true)
        cancelled.stringValue = "Cancelled"
        #expect(coordinator.control(cancelled, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(cancelled.superview == nil)
        #expect(try folder.loadEdit().fixes.isEmpty)
        coordinator.beginFix(range)
        let saved = try #require(text.subviews.compactMap { $0 as? NSTextField }.first)
        saved.stringValue = "New words"
        #expect(coordinator.control(saved, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        let task = try #require(model.fixTask)
        await task.value
        #expect(saved.superview == nil)
        #expect(try folder.loadEdit().fixes.count == 1)
        #expect(try folder.loadTranscripts().transcripts.values.first?.words.map(\.text) == ["New words", "word2"])
    }

    private func view(_ coordinator: TranscriptTextView.Coordinator) -> TranscriptNSTextView {
        let text = TranscriptNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        text.coordinator = coordinator
        text.delegate = coordinator
        coordinator.textView = text
        coordinator.update(version: coordinator.model.readingVersion, time: coordinator.model.currentTime, playing: false)
        return text
    }

    private func fixture() throws -> ProjectFolder {
        let folder = try ProjectFolder.create(at: FileManager.default.temporaryDirectory.appending(path: "cuecan-transcript-interactions-\(UUID())"), title: "Transcript interaction fixture")
        let project = try folder.updateProject {
            $0.addSource(name: "Fixture", origin: .recorded, tracks: [
                SourceTrack(kind: .camera, file: .inProject("recordings/missing.mov"), media: MediaInfo(duration: 3,
                    video: .init(width: 320, height: 180, frameRate: 30, captureRate: 30, codec: "avc1"))),
            ])
        }
        let source = try #require(project.sources.first)
        try folder.addTranscript(TranscriptDraft(engine: "fixture", silenceDetector: "fixture", language: "en", audioDuration: 3,
            items: (0..<3).map { .word(.init(text: "word\($0)", start: Double($0), end: Double($0) + 0.5)) }), for: source.id)
        try folder.updateEdit(author: .app, reason: "Fixture") { $0.addWholeSource(source) }
        return folder
    }
}

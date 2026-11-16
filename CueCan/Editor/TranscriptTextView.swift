import AppKit
import ProjectKit
import SwiftUI

/// The transcript's text (docs/ui.md, "The transcript in the inspector"; docs/decisions.md, 69), edited in
/// place: typing never changes it; Delete cuts the picked words, rounded out to whole words; with only a
/// caret, Backspace cuts the word before it and Forward Delete the word after. Right-click for Cut, Fix
/// Text…, Put Back, Play from Here and Copy. ⌘F finds.
struct TranscriptTextView: NSViewRepresentable {
    let model: EditorModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        // Chip and rail drawing uses NSLayoutManager. Start with TextKit 1 instead of switching
        // away from TextKit 2 inside the first draw, which leaves the words invisible until rebuilt.
        let text = TranscriptNSTextView(usingTextLayoutManager: false)
        text.coordinator = context.coordinator
        text.delegate = context.coordinator
        text.isEditable = true
        text.isSelectable = true
        text.isRichText = false
        text.allowsUndo = false
        text.drawsBackground = false
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.smartInsertDeleteEnabled = false
        text.textContainerInset = NSSize(width: 4, height: 12)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("Transcript")
        scroll.documentView = text
        context.coordinator.textView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.update(version: model.readingVersion, time: model.currentTime, playing: model.isPlaying)
        coordinator.follow(selection: model.selection)
        if let words = model.editingWords {
            Task { @MainActor in
                guard model.editingWords == words else { return }
                model.editingWords = nil
                coordinator.beginFix(words)
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
        var model: EditorModel
        weak var textView: TranscriptNSTextView?
        private(set) var document = TranscriptDocument(reading: nil, pending: nil, transcripts: TranscriptIndex([]))
        private var version = -1
        private var playing: NSRange?
        /// The selection this view last gave the editor, so following it back doesn't move the caret.
        private var sentSelection: EditorSelection = .none
        private enum FixState {
            case reading
            case editing(range: ItemRange, field: NSTextField)
        }
        private var fixState = FixState.reading
        /// Set while this view moves its own selection (rebuilding the text, following a selection made elsewhere,
        /// placing the caret after a cut), so the playhead follows only the creator.
        private var isMovingSelection = false

        private func movingSelection(_ change: () -> Void) {
            let outer = isMovingSelection
            isMovingSelection = true
            defer { isMovingSelection = outer }
            change()
        }

        init(model: EditorModel) {
            self.model = model
        }

        /// Rebuilds the text when the transcript changed, keeping the picked words picked, and marks the word
        /// being played.
        func update(version: Int, time: TimeInterval, playing isPlaying: Bool) {
            guard let textView else { return }
            if version != self.version {
                self.version = version
                if case .editing(let range, _) = fixState,
                   (try? model.transcripts.transcript(containing: range)) == nil { endFix() }
                let selected = textView.selectedRange()
                let kept = document.pieces(in: selected).map(\.token.id)
                let caretBefore = selected.length == 0 ? document.word(after: selected.location)?.token.id : nil
                document = TranscriptDocument(reading: model.reading, pending: model.pendingFix, transcripts: model.transcripts)
                movingSelection {
                    textView.textStorage?.setAttributedString(document.text)
                    if let first = kept.first, let last = kept.last, let from = document.range(of: first), let to = document.range(of: last) {
                        textView.setSelectedRange(NSUnionRange(from, to))
                    } else if let caretBefore, let range = document.range(of: caretBefore) {
                        textView.setSelectedRange(NSRange(location: range.location, length: 0))
                    } else {
                        textView.setSelectedRange(NSRange(location: min(selected.location, document.text.length), length: 0))
                    }
                }
                textView.updateToolTips()
                textView.needsDisplay = true
            }
            let now = document.piece(playingAt: time)?.range
            if now != playing {
                playing = now
                textView.playing = now
                if isPlaying, let now, !textView.visibleRect.contains(textView.rect(for: now)) {
                    textView.scrollRangeToVisible(now)
                }
            }
        }

        /// Shows words picked elsewhere, such as by Claude or by Undo, as picked here.
        func follow(selection: EditorSelection) {
            guard selection != sentSelection, let textView else { return }
            sentSelection = selection
            if selection.isEmpty, textView.selectedRange().length > 0 {
                movingSelection { textView.setSelectedRange(NSRange(location: textView.selectedRange().location, length: 0)) }
                return
            }
            guard let range = selection.wordRange, let transcript = try? model.transcripts.transcript(containing: range),
                  let time = try? CutPointSnapper(transcript: transcript).timeRange(for: range)
            else { return }
            let inside = document.pieces.indices.filter { index in
                let piece = document.pieces[index]
                return piece.token.source == transcript.source && piece.token.sourceRange.start >= time.start - 0.001
                    && piece.token.sourceRange.end <= time.end + 0.001
            }
            // A word id can play in several clips. A single text selection must not bridge the
            // unrelated words between those occurrences; follow one occurrence near the playhead.
            // An occurrence ends only where other text comes between, so words running on across
            // a split into the next clip stay one occurrence.
            var runs: [[TranscriptDocument.Piece]] = []
            var previousIndex: Int?
            for index in inside {
                if let previousIndex, index == previousIndex + 1 {
                    runs[runs.count - 1].append(document.pieces[index])
                } else { runs.append([document.pieces[index]]) }
                previousIndex = index
            }
            func distance(_ run: [TranscriptDocument.Piece]) -> TimeInterval {
                guard let start = run.first?.token.timeline?.start, let end = run.last?.token.timeline?.end else { return .infinity }
                return max(0, start - model.currentTime, model.currentTime - end)
            }
            var occurrence = runs.first ?? []
            for run in runs.dropFirst() where distance(run) < distance(occurrence) { occurrence = run }
            guard let first = occurrence.first, let last = occurrence.last else { return }
            let union = NSUnionRange(first.range, last.range)
            if textView.selectedRange() != union {
                movingSelection { textView.setSelectedRange(union) }
                textView.scrollRangeToVisible(union)
            }
        }

        // MARK: Picking

        /// The picked pieces, rounded out to whole words.
        var picked: [TranscriptDocument.Piece] {
            textView.map { document.pieces(in: $0.selectedRange()) } ?? []
        }

        func ranges(of pieces: [TranscriptDocument.Piece]) -> [ItemRange] {
            guard let first = pieces.first, let last = pieces.last else { return [] }
            return model.reading?.itemRanges(from: first.token.id, through: last.token.id) ?? []
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            // A click on a silence picks all of it.
            if new.length == 0, let piece = document.piece(at: new.location), piece.token.text == nil, new.location > piece.range.location {
                return piece.range
            }
            return new
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            let pieces = picked
            let words = pieces.filter { $0.token.text != nil }
            var selection = EditorSelection.none
            if let first = words.first, let last = words.last,
               let range = model.reading?.wordRange(from: first.token.id, through: last.token.id) {
                selection = .words(range)
            }
            sentSelection = selection
            if model.selection != selection, model.selection.isEmpty || model.selection.wordRange != nil { model.selection = selection }
            if !isMovingSelection, isFromTheCreator { movePlayheadToCaret() }
        }

        /// Whether the selection just changed because the creator clicked, dragged or pressed a key in the
        /// text. `NSApp.currentEvent` stays set after its event is handled, so it can't tell the view's own
        /// moves apart from the creator's on its own; those are marked with ``isMovingSelection``.
        private var isFromTheCreator: Bool {
            guard let textView, textView.window?.firstResponder === textView, let event = NSApp.currentEvent else { return false }
            return [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .keyDown].contains(event.type)
        }

        /// The playhead follows the caret: to the start of the first picked word,
        /// or of the word after the caret. A word that's cut (in Full) moves it to the next thing that plays.
        private func movePlayheadToCaret() {
            guard let textView else { return }
            let selected = textView.selectedRange()
            let from = selected.length > 0 ? picked.first?.range.location : document.word(after: selected.location)?.range.location
            guard let from,
                  let start = document.pieces.first(where: { $0.range.upperBound > from && $0.token.timeline != nil })?.token.timeline?.start,
                  abs(start - model.currentTime) > 0.001
            else { return }
            model.seek(to: start)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            false
        }

        // MARK: Editing

        /// Delete, ⌫ and ⌦: cuts the picked words, or the word before or after the caret.
        func delete(forward: Bool) {
            guard let textView else { return }
            let selected = textView.selectedRange()
            var pieces = picked
            if pieces.isEmpty {
                let word = forward ? document.word(after: selected.location) : document.word(before: selected.location)
                pieces = word.map { [$0] } ?? []
            }
            let live = pieces.filter { !$0.token.isCut }
            guard !live.isEmpty else { return NSSound.beep() }
            // The caret stays where the cut words were.
            let after = document.pieces.first { $0.range.location >= (pieces.last?.range.upperBound ?? 0) && !$0.token.isCut }
            model.cutTranscript(ranges(of: live))
            if let after, model.transcriptMode == .edit {
                // The text still has the times from before the cut, so this mustn't move the playhead.
                movingSelection { textView.setSelectedRange(NSRange(location: after.range.location, length: 0)) }
            }
        }

        func putBack() {
            model.putBack(ranges(of: picked))
        }

        func playFromHere() {
            guard let textView else { return }
            let location = textView.selectedRange().location
            let start = picked.first?.token.timeline?.start
                ?? document.pieces.first { $0.range.location >= location && $0.token.timeline != nil }?.token.timeline?.start
            guard let start else { return NSSound.beep() }
            model.play(from: start)
        }

        func copyWords() {
            let text = picked.compactMap(\.token.text).joined(separator: " ")
            guard !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        // MARK: Fix Text…

        /// Turns the words into a field right there in the text. Return saves, Esc leaves it.
        func beginFix(_ range: ItemRange? = nil) {
            guard let textView, let reading = model.reading else { return }
            let words: [TranscriptDocument.Piece]
            if let range {
                follow(selection: .words(range))
                words = picked.filter { $0.token.text != nil }
            } else {
                words = picked.filter { $0.token.text != nil }
            }
            guard let first = words.first, let last = words.last,
                  let itemRange = reading.wordRange(from: first.token.id, through: last.token.id)
            else { return NSSound.beep() }
            endFix()
            model.pause()
            let span = NSUnionRange(first.range, last.range)
            let rect = textView.rect(for: span)
            let field = TranscriptFixField(string: words.compactMap(\.token.text).joined(separator: " "))
            field.font = TranscriptDocument.font
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.usesSingleLineMode = false
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.delegate = self
            field.setAccessibilityLabel("Fix the words")
            let x = textView.textContainerOrigin.x + TranscriptDocument.railWidth - 4
            let width = textView.bounds.width - x - 8
            field.frame = NSRect(x: x, y: rect.minY - 3, width: width, height: max(rect.height + 6, 24))
            textView.addSubview(field)
            // NSTextView normally exposes only its text, rather than controls placed over it.
            textView.setAccessibilityChildren([field])
            fixState = .editing(range: itemRange, field: field)
            textView.window?.makeFirstResponder(field)
        }

        func endFix() {
            if case .editing(_, let field) = fixState {
                fixState = .reading
                field.removeFromSuperview()
                textView?.setAccessibilityChildren(nil)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if case .editing(let range, let field) = fixState { model.fixText(field.stringValue, for: range) }
                endFix()
                self.textView?.window?.makeFirstResponder(self.textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                endFix()
                self.textView?.window?.makeFirstResponder(self.textView)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            // Clicking away leaves the words as they were.
            if case .editing(_, let field) = fixState, (notification.object as? NSTextField) === field { endFix() }
        }

        // MARK: The rail

        /// Clicking an app's icon or a window's mark moves the playhead there.
        func railClicked(at point: NSPoint) -> Bool {
            guard let textView else { return false }
            for rail in document.rails {
                for tick in rail.ticks {
                    let line = textView.rect(for: NSRange(location: tick.location, length: 1))
                    if abs(point.y - line.midY) < 8, let time = tick.time { model.seek(to: time); return true }
                }
                let top = textView.rect(for: NSRange(location: rail.range.location, length: 1))
                if rail.front != nil, point.y >= top.minY - 2, point.y <= top.minY + 20, let time = rail.time {
                    model.seek(to: time)
                    return true
                }
            }
            return false
        }

        func menu() -> NSMenu {
            let menu = NSMenu()
            let pieces = picked
            let live = pieces.filter { !$0.token.isCut }
            func add(_ title: String, _ enabled: Bool, _ action: @escaping @MainActor () -> Void) {
                let item = ClosureMenuItem(title: title, action: action)
                item.isEnabled = enabled
                menu.addItem(item)
            }
            menu.autoenablesItems = false
            add("Cut", !live.isEmpty) { [weak self] in self?.delete(forward: false) }
            let words = pieces.filter { $0.token.text != nil }
            let fixable = words.first.flatMap { first in words.last.flatMap { model.reading?.wordRange(from: first.token.id, through: $0.token.id) } } != nil
            add("Fix Text…", fixable) { [weak self] in self?.beginFix() }
            if pieces.contains(where: \.token.isCut) {
                add("Put Back", true) { [weak self] in self?.putBack() }
            }
            menu.addItem(.separator())
            add("Play from Here", true) { [weak self] in self?.playFromHere() }
            add("Copy", !words.isEmpty) { [weak self] in self?.copyWords() }
            return menu
        }
    }
}

/// The text view under the transcript: draws the rail, the silence chips and blocks, and the word being
/// played, and turns Delete into cutting.
final class TranscriptNSTextView: NSTextView {
    weak var coordinator: TranscriptTextView.Coordinator?
    /// The word or silence being played.
    var playing: NSRange? { didSet { if playing != oldValue { needsDisplay = true } } }
    private var icons: [String: NSImage] = [:]

    /// The keys this view takes rather than the editor: moving the caret, picking, deleting, copying and
    /// finding. Everything else, Space and J, K and L among them, still drives the editor.
    func takes(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch event.keyCode {
        case 51, 117: return flags.isEmpty || flags == .option
        case 123, 124, 125, 126, 115, 119, 116, 121: return true
        default:
            guard flags == .command || flags == [.command, .shift] || flags == [.command, .option] else { return false }
            return ["c", "a", "f", "g", "e"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
        }
    }

    override func deleteBackward(_ sender: Any?) { coordinator?.delete(forward: false) }
    override func deleteForward(_ sender: Any?) { coordinator?.delete(forward: true) }
    override func deleteWordBackward(_ sender: Any?) { coordinator?.delete(forward: false) }
    override func deleteWordForward(_ sender: Any?) { coordinator?.delete(forward: true) }
    override func delete(_ sender: Any?) { coordinator?.delete(forward: false) }
    override func cut(_ sender: Any?) { coordinator?.delete(forward: false) }
    override func copy(_ sender: Any?) { coordinator?.copyWords() }
    override func paste(_ sender: Any?) { NSSound.beep() }

    override func menu(for event: NSEvent) -> NSMenu? {
        // A right-click outside what's picked picks the word under it first.
        let point = convert(event.locationInWindow, from: nil)
        let location = characterIndexForInsertion(at: point)
        let selected = selectedRange()
        if !NSLocationInRange(location, selected), let piece = coordinator?.document.piece(at: location) {
            setSelectedRange(piece.range)
        }
        return coordinator?.menu()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if point.x < textContainerOrigin.x + TranscriptDocument.railWidth - 4, coordinator?.railClicked(at: point) == true { return }
        super.mouseDown(with: event)
    }

    /// Where a run of characters is drawn, in the view's coordinates.
    func rect(for range: NSRange) -> NSRect {
        guard let layoutManager, let textContainer, range.location != NSNotFound else { return .zero }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// The rects of a run of characters, one per line.
    private func lineRects(for range: NSRange) -> [NSRect] {
        guard let layoutManager, let textContainer else { return [] }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                              in: textContainer) { rect, _ in
            rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
        }
        return rects
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let coordinator else { return }
        let document = coordinator.document
        // Silences: chips after words, and a dashed block across the text for a long one.
        for piece in document.pieces where piece.token.text == nil {
            if piece.isBlock {
                let line = self.rect(for: piece.range)
                let block = NSRect(x: textContainerOrigin.x + TranscriptDocument.railWidth, y: line.minY - 4,
                                   width: bounds.width - textContainerOrigin.x - TranscriptDocument.railWidth - 8, height: line.height + 8)
                guard block.intersects(rect) else { continue }
                let path = NSBezierPath(roundedRect: block, xRadius: 6, yRadius: 6)
                path.setLineDash([4, 3], count: 2, phase: 0)
                path.lineWidth = 1
                NSColor.separatorColor.setStroke()
                path.stroke()
            } else {
                for chip in lineRects(for: piece.range) where chip.intersects(rect) {
                    NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
                    NSBezierPath(roundedRect: chip.insetBy(dx: 0, dy: 1), xRadius: 4, yRadius: 4).fill()
                }
            }
        }
        // The fix being timed.
        for pending in document.pendingRanges {
            for line in lineRects(for: pending) {
                NSColor.secondaryLabelColor.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: line.insetBy(dx: -2, dy: 0), xRadius: 4, yRadius: 4).fill()
            }
        }
        // The word being played.
        if let playing {
            for line in lineRects(for: playing) {
                NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
                NSBezierPath(roundedRect: line.insetBy(dx: -2, dy: 0), xRadius: 4, yRadius: 4).fill()
            }
        }
        drawRail(document, in: rect)
    }

    private func drawRail(_ document: TranscriptDocument, in dirty: NSRect) {
        let x = textContainerOrigin.x + 2
        for rail in document.rails {
            guard rail.range.length > 0 else { continue }
            let top = rect(for: NSRange(location: rail.range.location, length: 1))
            let bottom = rect(for: NSRange(location: rail.range.upperBound - 1, length: 1))
            let span = NSRect(x: x, y: top.minY, width: 20, height: bottom.maxY - top.minY)
            guard span.intersects(dirty), let front = rail.front else { continue }
            let iconRect = NSRect(x: x, y: top.minY + 1, width: 16, height: 16)
            icon(for: front).draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if bottom.maxY > iconRect.maxY + 6 {
                NSColor.separatorColor.setFill()
                NSRect(x: iconRect.midX - 0.5, y: iconRect.maxY + 3, width: 1, height: bottom.maxY - iconRect.maxY - 3).fill()
            }
            for tick in rail.ticks {
                let line = rect(for: NSRange(location: tick.location, length: 1))
                NSColor.secondaryLabelColor.setFill()
                NSRect(x: iconRect.midX - 3, y: line.midY - 0.75, width: 6, height: 1.5).fill()
            }
        }
    }

    private func icon(for front: ScreenFront) -> NSImage {
        let key = front.bundleID ?? front.app
        if let icon = icons[key] { return icon }
        let made: NSImage
        if let id = front.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            made = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        } else {
            made = NSImage(systemSymbolName: "macwindow", accessibilityDescription: front.app) ?? NSImage()
        }
        icons[key] = made
        return made
    }

    /// Hovering the rail names the app and window.
    func updateToolTips() {
        removeAllToolTips()
        guard let document = coordinator?.document else { return }
        let x = textContainerOrigin.x + 2
        func name(_ front: ScreenFront) -> String {
            front.window.map { $0.isEmpty ? front.app : "\(front.app) — \($0)" } ?? front.app
        }
        for rail in document.rails where rail.range.length > 0 {
            if let front = rail.front {
                let top = rect(for: NSRange(location: rail.range.location, length: 1))
                addToolTip(NSRect(x: x, y: top.minY, width: 18, height: 18), owner: name(front) as NSString, userData: nil)
            }
            for tick in rail.ticks {
                let line = rect(for: NSRange(location: tick.location, length: 1))
                addToolTip(NSRect(x: x, y: line.midY - 6, width: 18, height: 12), owner: name(tick.front) as NSString, userData: nil)
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { updateToolTips() }
    }
}

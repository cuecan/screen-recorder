import AppKit
import ProjectKit

/// The editor's keys (docs/ui.md, E1 to E3, "Keys follow the usual professional-editor defaults"): a base set, plus DaVinci
/// Resolve's where they don't clash (⇧Delete, ⇧[ and ⇧]).
///
/// A local key monitor, so the keys work wherever the focus is in the editor's window, except while typing
/// in a text field, where they're the field's.
final class EditorKeys {
    private var monitor: Any?
    private weak var window: NSWindow?

    func start(model: EditorModel, in window: NSWindow?) {
        stop()
        guard let window else { return }
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window else { return event }
            // A popover receives its key in a separate window. Consume Escape before AppKit closes
            // that window and forwards the same cancel action to the editor underneath it.
            if event.keyCode == Key.escape.rawValue,
               event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
               model.inspectorPopover != nil,
               window.attachedSheet == nil, NSApp.modalWindow == nil {
                _ = Self.handle(event, model: model)
                return nil
            }
            guard event.window == window,
                  window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil
            else { return event }
            // The transcript takes the keys that move its caret, pick, delete, copy and find; the rest drive the
            // editor, since typing never changes the transcript (docs/decisions.md, 69).
            if let transcript = event.window?.firstResponder as? TranscriptNSTextView {
                if transcript.takes(event) { return event }
                if Self.handle(event, model: model) { return nil }
                // Menu shortcuts and Tab go on; typed letters go nowhere.
                return event.modifierFlags.contains(.command) || event.keyCode == 48 ? event : nil
            }
            if let responder = event.window?.firstResponder as? NSTextView, responder.isEditable { return event }
            return Self.handle(event, model: model) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private enum Key: UInt16 {
        case a = 0, s = 1, h = 4, z = 6, x = 7, b = 11, t = 17, equals = 24, minus = 27, o = 31, rightBracket = 30, leftBracket = 33
        case i = 34, l = 37, j = 38, quote = 39, k = 40, semicolon = 41, comma = 43, n = 45, m = 46, period = 47
        case space = 49, delete = 51, escape = 53, home = 115, forwardDelete = 117, end = 119
        case left = 123, right = 124, down = 125, up = 126
    }

    /// Handles a key, returning whether it was the editor's.
    static func handle(_ event: NSEvent, model: EditorModel) -> Bool {
        guard let key = Key(rawValue: event.keyCode) else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let shift = flags == .shift
        let plain = flags.isEmpty
        let command = flags == .command
        let option = flags == .option
        // Empty and failed previews still allow Undo; they cannot accept timeline edits.
        guard model.timeline != nil || (key == .z && flags.contains(.command)) || (key == .escape && plain) else { return false }

        switch key {
        case .space where plain: model.togglePlayback()
        case .j where plain: model.shuttle(-1)
        case .k where plain: model.shuttle(0)
        case .l where plain: model.shuttle(1)
        case .left where plain || shift: model.step(frames: shift ? -10 : -1)
        case .right where plain || shift: model.step(frames: shift ? 10 : 1)
        case .up where plain, .semicolon where plain: model.jumpToEdit(forward: false)
        case .down where plain, .quote where plain: model.jumpToEdit(forward: true)
        case .home where plain: model.seek(to: 0)
        case .end where plain: model.seek(to: model.duration)
        case .a where plain: model.tool = .select
        case .b where plain: model.pickBlade()
        case .t where plain: model.tool = .trim
        case .b where command: model.blade(at: Timecode(frameDuration: model.frameDuration).frameTime(nearest: model.currentTime))
        case .n where plain: model.snapping.toggle()
        case .delete where plain || shift, .forwardDelete where plain: model.deleteSelection()
        case .leftBracket where option || shift: model.trimToPlayhead(.start)
        case .rightBracket where option || shift: model.trimToPlayhead(.end)
        case .comma where plain || shift: model.nudgeSelectedEdge(frames: shift ? -10 : -1)
        case .period where plain || shift: model.nudgeSelectedEdge(frames: shift ? 10 : 1)
        case .i where plain: model.mark(in: true)
        case .o where plain: model.mark(in: false)
        case .x where option: model.clearMarks()
        case .m where plain: model.addMarker()
        case .equals where command: model.zoom = TimelineZoom.clamped(model.zoom * 1.5)
        case .minus where command: model.zoom = TimelineZoom.clamped(model.zoom / 1.5)
        case .z where shift: model.fitRequest += 1
        case .z where command: model.undo()
        case .z where flags == [.command, .shift]: model.redo()
        case .h where shift: model.freezeSelection()
        case .n where shift:
            let clips = model.selection.clipIDs.isEmpty ? Set(model.edit?.placement(at: model.currentTime).map { [$0.clip.id] } ?? []) : model.selection.clipIDs
            model.setSpeed(.normal, for: clips)
        case .escape where plain:
            if model.inspectorPopover != nil { model.inspectorPopover = nil }
            else if model.tool == .blade { model.tool = .select }
            else { model.selection = .none }
        default: return false
        }
        return true
    }
}

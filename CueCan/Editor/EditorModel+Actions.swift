import AppKit
import Foundation
import ProjectKit
import RenderKit

/// The editor's gestures and keys (docs/ui.md, E2), each one of the edit model's operations, the same one
/// Claude's matching tool runs, made as the creator: edges placed this way are marked as placed by hand,
/// so Claude's broad passes leave them alone (docs/decisions.md, 56).
extension EditorModel {
    // MARK: - The blade and trimming

    /// ⌘B, or a click with the blade: divides the clip there, removing nothing (`split_clip`).
    func blade(at time: TimeInterval) {
        change("Blade at \(clock(time))") { edit, _ in
            _ = try edit.split(at: time, byHand: true)
        }
    }

    /// Dragging a clip's edge: trims it, or, outward, brings back what was cut (`cut` / `keep`).
    ///
    /// - Parameter rolling: The Trim tool on a join that rolls: the neighbour's edge goes with this one.
    func setEdge(_ edge: ClipEdge, of clip: ClipID, toSourceTime time: TimeInterval, rolling: Bool = false) {
        let duration = sourceDuration(of: clip)
        if change(rolling ? "Rolled the join at the \(edge.rawValue) of \(clip)" : "Trimmed the \(edge.rawValue) of \(clip)", { edit, _ in
            _ = try edit.setEdge(edge, of: clip, to: time, sourceDuration: duration, byHand: true, rolling: rolling)
        }) {
            selection = .clipEdge(clip: clip, edge: edge)
        }
    }

    /// ⌥[ and ⌥] (⇧[ and ⇧] in Resolve): trims the clip at the playhead so it starts or ends there.
    func trimToPlayhead(_ edge: ClipEdge) {
        guard let edit, let placed = edit.placement(at: currentTime) else { return NSSound.beep() }
        let duration = sourceDuration(of: placed.clip.id)
        let time = currentTime
        change("Trimmed the \(edge.rawValue) of \(placed.clip.id) to the playhead") { edit, _ in
            _ = try edit.trim(edge, toTimeline: time, sourceDuration: duration, byHand: true)
        }
    }

    /// , and . nudge the selected edge a frame; ⇧, and ⇧. ten (`nudge_cut`). A join rolls only with the Trim
    /// tool, as it does under the pointer.
    func nudgeSelectedEdge(frames: Int) {
        guard let picked = selection.edge else {
            // A nudge moves an edge, not a whole clip.
            problem = "Click the start or end of a clip to pick the edge to nudge."
            return NSSound.beep()
        }
        guard let edit, let clip = edit.main.first(where: { $0.id == picked.clip }) else { return NSSound.beep() }
        let seconds = clip.speed.sourceOffset(forTimelineFrames: frames, frameDuration: frameDuration)
        var target: TimeInterval?
        let rolling = tool == .trim
        if change("Nudged the \(picked.edge.rawValue) of \(clip.id) by \(frames) \(abs(frames) == 1 ? "frame" : "frames")", { edit, transcripts in
            _ = try edit.nudge(picked.edge, of: picked.clip, by: seconds, transcripts: transcripts, byHand: true, rolling: rolling)
            if let changed = edit.main.first(where: { $0.id == picked.clip }) {
                target = picked.edge == .start ? changed.playedRange.start : changed.playedRange.end
            }
        }), let target {
            keyboardTrimFeedback = TrimLoupeRequest(edit: edit, clip: picked.clip, edge: picked.edge, sourceTime: target,
                                                   sourceDuration: sourceDuration(of: picked.clip), frameDuration: frameDuration, rolling: rolling)
        }
    }

    // MARK: - Deleting

    /// Delete and ⇧Delete: removes the selection and closes the gap (`cut`). There are never black gaps.
    func deleteSelection() {
        if selection.isEmpty {
            guard let range = markedRange else { return NSSound.beep() }
            if change("Cut \(clock(range.start))–\(clock(range.end))", { edit, _ in
                _ = try edit.cut(timeline: range, byHand: true)
            }) { clearMarks() }
            return
        }
        let changed: Bool
        switch selection {
        case .freeze(let id):
            changed = change("Removed \(id)") { edit, _ in try edit.removeFreeze(id) }
        case .overlays(let ids):
            changed = change("Removed \(ids.count == 1 ? "an overlay" : "\(ids.count) overlays")") { edit, _ in
                for id in ids { try edit.removeOverlay(id) }
            }
        case .words(let range):
            changed = change("Cut \(range)") { edit, transcripts in _ = try edit.cut(range, transcripts: transcripts, byHand: true) }
        case .clips, .clipEdge:
            let ids = selection.clipIDs
            changed = change("Cut \(ids.sorted().map(\.description).joined(separator: ", "))") { edit, _ in
                for id in ids { try edit.removeClip(id) }
            }
        case .none:
            return
        }
        if changed { selection = .none }
    }

    // MARK: - Retiming

    /// ⇧H: holds the screen over the marked or selected range, on the frame at its start (`freeze_screen`).
    func freezeSelection() {
        let range = selectedRange ?? selectedClip.flatMap { clip in edit?.placements.first { $0.clip.id == clip.id }?.timeline }
        guard let range else { return NSSound.beep() }
        change("Froze the screen \(clock(range.start))–\(clock(range.end))") { edit, _ in
            _ = try edit.freeze(timeline: range)
        }
    }

    /// ⇧N, or the inspector: a clip's speed (`set_speed`).
    func setSpeed(_ speed: ClipSpeed, for clips: Set<ClipID>) {
        guard !clips.isEmpty else { return NSSound.beep() }
        change(speed.isNormal ? "Normal speed" : "Speed \(speed.label)") { edit, _ in
            for id in clips { _ = try edit.setSpeed(speed, for: id) }
        }
    }

    /// Audio retiming changes the sound policy without copying one clip's rate onto the selection.
    func setSpeedSound(_ sound: ClipSpeed.Sound, for clips: Set<ClipID>) {
        change(sound == .muted ? "Muted retimed sound" : "Kept retimed pitch") { edit, _ in
            for id in clips {
                guard let clip = edit.main.first(where: { $0.id == id }),
                      let speed = ClipSpeed(rate: clip.speed.rate, sound: sound) else { continue }
                _ = try edit.setSpeed(speed, for: id)
            }
        }
    }

    func setFreezeRange(_ id: FreezeID, to range: TimeRange) {
        change("Stretched \(id)") { edit, _ in try edit.setFreezeRange(id, to: range) }
    }

    // MARK: - Overlays

    /// Dropping or choosing a file: an overlay over the marked range, the selected words, or a few seconds
    /// from the playhead (`place_broll`).
    func addOverlay(_ url: URL, at time: TimeInterval? = nil) {
        let media = Overlay.Media.file(at: url)
        let start = time ?? currentTime
        let range = time == nil ? (selectedRange ?? TimeRange(start: start, end: min(duration, start + 3))) : TimeRange(start: start, end: min(duration, start + 3))
        guard range.duration > 0.05 else { return NSSound.beep() }
        var added: ClipID?
        if change("Placed \(url.lastPathComponent)", { edit, _ in
            added = try edit.placeOverlay(media, overTimeline: range, placement: .inScreensPlace).id
        }), let added {
            selection = .overlays([added])
        }
    }

    /// Dragging an overlay, or one of its ends, over other time (`place_broll`).
    func moveOverlay(_ id: ClipID, to range: TimeRange) {
        guard range.duration > 0.05 else { return }
        change("Moved \(id)") { edit, _ in try edit.moveOverlay(id, overTimeline: range) }
    }

    func updateOverlay(_ id: ClipID, _ reason: String, _ body: @escaping (inout Overlay) -> Void) {
        change(reason) { edit, _ in try edit.updateOverlay(id, body) }
    }

    func replaceOverlay(_ id: ClipID, with url: URL) {
        updateOverlay(id, "Replaced \(id)") { $0.media = .file(at: url) }
    }

    // MARK: - Words

    /// What a run of words reads as.
    func text(of words: ItemRange) -> String {
        guard let edit, let transcript = try? transcripts.transcript(containing: words),
            let indices = try? CutPointSnapper(transcript: transcript).indices(of: words)
        else { return "" }
        let items = transcript.items[indices].compactMap { item -> Word? in if case .word(let word) = item { word } else { nil } }
        let texts = edit.exportTexts(of: transcript, spellings: spellings[transcript.source])
        return items.compactMap { texts[$0.id] }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Layouts, look and sound

    /// Chooses a layout button for each clip independently. An existing card keeps its own parameters;
    /// another layout gets its take's card, so a mixed selection never copies the first clip's settings.
    func setLayout(_ choice: LayoutChoice, for clips: Set<ClipID>) {
        let project = project
        let output = shape
        change("Layout of \(clips.sorted().map(\.description).joined(separator: ", "))") { edit, _ in
            for id in clips {
                guard let clip = edit.main.first(where: { $0.id == id }), let source = project?.source(clip.source) else { continue }
                let current = LayoutGeometry.resolved(clip.layout, in: output, pictures: ClipPictures(source: source))
                let layout = choice.layout(current: current, recorded: source.layout, destination: project?.effectiveFormat.destination ?? .landscape)
                try edit.setLayout(layout, for: id, recorded: source.layout)
            }
        }
    }

    /// Changes the card of every chosen clip that shows one, each from its own, so clips with different cards
    /// can take one change together (docs/decisions.md, 89).
    func changeCards(_ reason: String, for clips: Set<ClipID>, _ body: @escaping (inout Card) -> Void) {
        let project = project
        let output = shape
        change(reason) { edit, _ in
            for id in clips {
                guard let clip = edit.main.first(where: { $0.id == id }), let source = project?.source(clip.source),
                    case .card(var card) = LayoutGeometry.resolved(clip.layout, in: output, pictures: ClipPictures(source: source))
                else { continue }
                body(&card)
                try edit.setLayout(.card(card), for: id, recorded: source.layout)
            }
        }
    }

    /// Changes what every clip shares: rounded corners, the background, mirroring.
    func setLook(_ reason: String, _ body: @escaping (inout EditLook) -> Void) {
        change(reason) { edit, _ in body(&edit.look) }
    }

    /// Changes the camera side or captions of each of these clips (docs/decisions.md, 68).
    func setClipLook(_ reason: String, for clips: Set<ClipID>, _ body: @escaping (inout ClipLook) -> Void) {
        change(reason) { edit, _ in
            for id in clips { try edit.changeLook(for: id, body) }
        }
    }

    func setMuted(_ muted: Bool, for clips: Set<ClipID>) {
        setSound(ClipSoundChange(isMuted: muted), for: clips, muted ? "Muted" : "Unmuted")
    }

    /// Sets clips' levels or Mute (docs/decisions.md, 71): the level line, the inspector's Sound section and
    /// `set_clip_sound` are the same operation.
    func setSound(_ sound: ClipSoundChange, for clips: Set<ClipID>, _ reason: String? = nil) {
        let ordered = edit?.main.map(\.id).filter { clips.contains($0) } ?? []
        guard !sound.isEmpty, !ordered.isEmpty else { return }
        let names = ordered.count == 1 ? "\(ordered[0])" : "\(ordered.count) clips"
        let described = reason ?? [
            sound.voiceLevel.map { "Voice \(SoundLevel.label($0))" },
            sound.systemAudioLevel.map { "System audio \(SoundLevel.label($0))" },
        ].compactMap { $0 }.joined(separator: ", ") + " on \(names)"
        change(described) { edit, _ in try edit.setSound(sound, for: ordered) }
    }

    /// Sets the level of an overlay's own sound, in dB.
    func setLevel(_ level: Double, forOverlay id: ClipID) {
        change("\(id) sound \(SoundLevel.label(level))") { edit, _ in try edit.setLevel(level, forOverlay: id) }
    }

    func setAudio(_ audio: ClipAudio?, for clips: Set<ClipID>) {
        change("Sound from \(audio?.source.description ?? "the clip")") { edit, _ in
            for index in edit.main.indices where clips.contains(edit.main[index].id) {
                edit.main[index].audio = audio?.source == edit.main[index].source ? nil : audio
            }
        }
    }


    /// Cleanup and Voice for one mic, then cleaning it again with the new settings.
    /// - Returns: Whether the edit was saved, so a control that already shows the choice can take it back.
    @discardableResult
    func setVoice(for source: SourceID, _ reason: String, processing: ProcessingCenter, _ body: @escaping (inout SourceAudioSettings) -> Void) -> Bool {
        var didChange = false
        let saved = change(reason, { edit, _ in
            var settings = edit.audio.settings(for: source)
            let before = settings
            body(&settings)
            guard settings != before else { return }
            edit.audio.set(settings, for: source)
            didChange = true
        })
        if saved, didChange { processing.process(folder) }
        return saved
    }

    func setFraming(_ framing: CameraFraming, slot: CameraSlot, for source: SourceID) {
        change("Framed the camera") { edit, _ in edit.setFraming(framing, slot: slot, for: source) }
    }

    // MARK: - Marks

    func mark(in isIn: Bool) {
        // A range is the edit target. Keeping a whole clip selected would make Delete remove that
        // clip instead of the range the creator just marked.
        selection = .none
        if isIn { markIn = currentTime } else { markOut = currentTime }
        if let markIn, let markOut, markOut < markIn { (self.markIn, self.markOut) = (markOut, markIn) }
    }

    func clearMarks() {
        markIn = nil
        markOut = nil
    }

    func addMarker() {
        if !markers.contains(where: { abs($0 - currentTime) < 0.01 }) { markers.append(currentTime) }
        markers.sort()
    }

    /// "1:02:15", minutes, seconds and frames at the edit's frame rate, as the transport shows the playhead.
    func clock(_ seconds: TimeInterval) -> String {
        Timecode(frameDuration: frameDuration).string(seconds)
    }

    // MARK: - Broad passes

    /// The clips the broad passes act on: the selected ones, or nil for the whole edit.
    var passScope: Set<ClipID>? { selection.clipIDs.isEmpty ? nil : selection.clipIDs }

    /// Remove Silences: shortens every pause longer than ``silenceThreshold`` to the default air, in the
    /// selected clips or the whole edit, as `remove_silences` does. Edges placed by hand stay put. One change,
    /// so one History entry and one undo; nothing to shorten changes nothing.
    func removeSilences() {
        let scope = passScope
        let threshold = silenceThreshold, air = Edit.defaultSilenceAir
        var count = 0
        let reason = "Shortened pauses over \(threshold.formatted()) s to \(air.formatted()) s\(Self.scopeNote(scope))"
        guard change(reason, { edit, transcripts in
            count = try edit.removeSilences(longerThan: threshold, leaving: air, transcripts: transcripts, in: scope)
        }) else { return }
        notice = count == 0
            ? "No pauses longer than \(threshold.formatted()) s to shorten\(Self.scopeNote(scope))."
            : "Shortened \(count) \(count == 1 ? "pause" : "pauses") to \(air.formatted()) s\(Self.scopeNote(scope))."
    }

    private static func scopeNote(_ scope: Set<ClipID>?) -> String {
        guard let scope else { return "" }
        return scope.count == 1 ? " in the selected clip" : " in the \(scope.count) selected clips"
    }
}


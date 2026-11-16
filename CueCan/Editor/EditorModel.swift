import AppKit
import AudioKit
import AVFoundation
import Foundation
import Observation
import ProjectKit
import RenderKit

/// One project open in the editor (docs/decisions.md, 54 to 61; docs/ui.md, E1 to E3): its files, the
/// preview of every output from one player, the playhead, the selection and the timeline's view.
///
/// Every gesture is one of the edit model's operations, the same ones Claude's tools use, saved with the
/// author `app`, so the creator and Claude never work on different things and ⌘Z undoes either. The
/// preview is rebuilt whenever `edit.json` changes, including when Claude changes it from the CLI.
@Observable
final class EditorModel {
    /// The editor's tools (A, B and T).
    typealias Tool = TimelineTool

    let folder: ProjectFolder
    private(set) var project: Project?
    private(set) var edit: Edit?
    private(set) var transcripts = TranscriptIndex([])
    private(set) var spellings: [SourceID: VocabularySpellings] = [:]
    private(set) var history: [EditHistory.Entry] = []
    private(set) var canRedo = false
    private(set) var timeline: EditTimeline?
    /// Word occurrences and source snap points change with project inputs, never with the playhead.
    private(set) var playedWords: [PlayedWord] = []
    private(set) var snapper = EditSnapper(transcripts: TranscriptIndex([]))
    /// The shape the creator last chose to show, if any (``shape``).
    private(set) var shownShape: OutputShape?
    /// The shown shape's place in the preview composition, and the composition's size.
    private(set) var panels: [(output: OutputShape, rect: CGRect)] = []
    private(set) var renderSize = CGSize(width: 1920, height: 1080)
    var problem: String?
    /// What a broad pass did, shown over the preview until the next change or Dismiss.
    var notice: String?
    /// Where the editor's own preferences are kept: the app's, but for tests.
    @ObservationIgnored private let preferences: UserDefaults
    static let silenceThresholdKey = "removeSilencesThreshold"
    /// How long a pause has to be before Remove Silences shortens it, in seconds to a tenth. It's the
    /// creator's taste, not part of an edit, so it's kept in the app's preferences for every project.
    var silenceThreshold = Edit.defaultSilenceThreshold {
        didSet {
            let kept = Edit.silenceThreshold(silenceThreshold)
            if kept != silenceThreshold { silenceThreshold = kept; return }
            if kept != oldValue { preferences.set(kept, forKey: Self.silenceThresholdKey) }
        }
    }
    /// A failed preview stays visible until a retry or a file change, independently of editing errors.
    var previewProblem: String? { previewLoad.problem }
    let player = AVPlayer()
    /// The frame held on screen while a new item replaces the playing one.
    let frameHold = FrameHold()
    /// A decoded frame can belong to the previous item's clock. Only present the replacement after
    /// its exact initial seek completes; AVPlayerLayer readiness alone is too early during a swap.
    private(set) var displayReadyItem: AVPlayerItem?
    private(set) var poster: NSImage?
    private var previewLoad = PreviewLoad()
    @ObservationIgnored private var seeking = PreviewSeeking()
    var isPreparing: Bool { previewLoad.state == .idle || previewLoad.isLoading }
    private(set) var currentTime: TimeInterval = 0
    private var playback = EditorPlayback()
    var isPlaying: Bool { playback.isPlaying }
    /// When the screen went still, by source, for the ruler's dots and snapping (docs/decisions.md, 58).
    private(set) var stillMoments: [SourceID: [TimeInterval]] = [:]
    /// The mic's loudness over time, by source, for the audio lane.
    private(set) var waveforms: [SourceID: Waveform] = [:]
    /// Each source's system audio, drawn thinner under its voice (docs/decisions.md, 71).
    private(set) var systemWaveforms: [SourceID: Waveform] = [:]

    var tool = Tool.select { didSet { if tool != .blade { keepsBlade = false } } }
    /// Whether the blade stays on after a cut. Off, it's for one cut and Select comes back: several cuts
    /// in a row are rare, so keeping it on is the extra step.
    private(set) var keepsBlade = false

    /// The blade button and B: the blade for one cut; again while it's on, kept on, and once more, back to one cut.
    func pickBlade() {
        if tool == .blade { keepsBlade.toggle() } else { tool = .blade }
    }

    /// After the blade tool cut a clip: Select comes back unless the blade is kept on.
    func bladeDidCut() {
        if tool == .blade, !keepsBlade { tool = .select }
    }
    var inspectorTab = InspectorTab.video {
        didSet { if inspectorTab != oldValue { inspectorPopover = nil } }
    }
    var inspectorPopover: InspectorPopover?
    /// The Voice preset each mic had when the Equalizer was switched off, to bring back when it's switched on.
    @ObservationIgnored var lastVoicePresets: [SourceID: VoiceSettings.Preset] = [:]
    /// The edge loupe also appears briefly for frame nudges made with the keyboard.
    var keyboardTrimFeedback: TrimLoupeRequest?
    /// Snapping (N): on by default (docs/decisions.md, 56).
    var snapping = true
    var selection: EditorSelection = .none {
        didSet {
            if selection != oldValue { cancelTransformPreview(); inspectorPopover = nil }
            if selection.clipIDs.isEmpty { clipPicking.clear() }
            // Only a selection the creator or an agent makes moves the inspector. A reload assigns the
            // selection again, to drop what an edit removed, and that mustn't pull the creator out of the
            // tab they chose: cutting words in the transcript with a clip still selected stays there.
            if selection != oldValue, !isPruningSelection {
                if selection.wordRange != nil { inspectorTab = .transcript }
                else if !selection.isEmpty, inspectorTab == .transcript { inspectorTab = .video }
            }
            if selection != oldValue { scheduleStateSave() }
        }
    }
    @ObservationIgnored private var isPruningSelection = false
    @ObservationIgnored private var clipPicking = ClipPicking()
    var markIn: TimeInterval? { didSet { scheduleStateSave() } }
    var markOut: TimeInterval? { didSet { scheduleStateSave() } }
    var markers: [TimeInterval] = [] { didSet { scheduleStateSave() } }
    /// The timeline's zoom, in points per second.
    var zoom: Double = 40
    var zoomExponent: Double {
        get { log2(zoom) }
        set { zoom = TimelineZoom.clamped(pow(2, newValue)) }
    }
    /// Asks the timeline to fit its width (⇧Z).
    var fitRequest = 0
    /// Explicit navigation reveals its target; a user can otherwise scroll away during playback.
    private(set) var seekRequest = 0
    /// Words to open Fix Text… on in the transcript.
    var editingWords: ItemRange?
    /// What the transcript shows: only what plays, or everything recorded (docs/ui.md, "The transcript in the
    /// inspector").
    var transcriptMode = TranscriptReading.Mode.edit { didSet { if transcriptMode != oldValue { rebuildReading() } } }
    /// The transcript laid out for the inspector, and a number that changes whenever it does.
    private(set) var reading: TranscriptReading?
    private(set) var readingVersion = 0
    /// A fix being timed, shown in the transcript until it's saved.
    var fixing = TranscriptFixing() {
        didSet { if fixing != oldValue { readingVersion += 1 } }
    }
    var pendingFix: TranscriptFixing.Request? { fixing.pending }
    @ObservationIgnored var fixTask: Task<Void, Never>?
    @ObservationIgnored let alignFix: FixAligner
    typealias FixAligner = @Sendable (String, ItemRange, URL) async -> [AlignedWord]?
    /// What was in front on screen, settled, by source, for the transcript's rail.
    private(set) var screenFronts: [SourceID: [ScreenFront]] = [:]
    /// The framing popover's source for each camera, kept while the editor is open.
    @ObservationIgnored private var framingSources: [SourceID: EditorFramingSource] = [:]
    @ObservationIgnored private(set) var frameDuration: TimeInterval = 1.0 / 30
    @ObservationIgnored private var watchedRevision: Int?
    @ObservationIgnored private var watchedFiles: [Date?] = []
    @ObservationIgnored private var stateSave: Task<Void, Never>?
    /// How many pixels tall the previews are on screen, and the scale the current preview was built at, so
    /// it's built as sharp as the display shows it (a 5K display shows a 540-pixel preview stretched 2×).
    @ObservationIgnored private var previewPixelHeight: Double = 0
    @ObservationIgnored private var builtScale: Double?
    @ObservationIgnored private var rescale: Task<Void, Never>?
    @ObservationIgnored private var posterTask: Task<Void, Never>?
    @ObservationIgnored private let framingPreview = FramingAudition()
    @ObservationIgnored private var auditionsFraming = false
    /// What the framing control in hand last asked to see, so a reload can show it again.
    @ObservationIgnored private var lastAudition: (picture: Edit.Picture, centerX: Double?, centerY: Double?, zoom: Double?)?
    /// Whether the pointer is still down. A framing audition with the pointer down is a drag in progress;
    /// one with the pointer up was left behind. Replaced in tests, which have no pointer.
    @ObservationIgnored var isPointerDown: () -> Bool = { NSEvent.pressedMouseButtons != 0 }
    /// What the playing item was built from, so a change to the mix alone can skip the rebuild.
    @ObservationIgnored private var playingInputs: RenderInputs?
    @ObservationIgnored private var mixRequest: UUID?
    /// The latest reload. A rebuild clears `mixRequest`, so it can't also say which reload is newest.
    @ObservationIgnored private var reloadRequest: UUID?
    private(set) var previewLoudness = PreviewLoudness()
    @ObservationIgnored private let loudnessRenderer = LoudnessPreviewRenderer()
    @ObservationIgnored private var loudnessTask: Task<Void, Never>?
    @ObservationIgnored private var rawComposition: BuiltComposition?
    @ObservationIgnored private var normalizedAudio: PreviewAudioFile?
    @ObservationIgnored private var waveformReads: [WaveformSource: (url: URL, offset: Double, request: UUID, task: Task<Void, Never>)] = [:]

    /// Auditions the same final-mix mastering as export; it never changes the edit or export settings.
    var normalizePreview: Bool {
        get { previewLoudness.isEnabled }
        set { setNormalizePreview(newValue) }
    }

    var duration: TimeInterval { timeline?.duration ?? edit?.duration ?? 0 }

    /// The framing popover for a source's camera: the Recording Panel's own (docs/ui.md, R8).
    func framing(_ source: SourceID) -> EditorFramingSource {
        if let existing = framingSources[source] { return existing }
        let made = EditorFramingSource(model: self, source: source)
        framingSources[source] = made
        return made
    }
    /// The shapes the take is made for, which Export offers.
    var outputs: [OutputShape] { project?.effectiveFormat.outputs ?? [.landscape] }

    /// The shape the editor shows: the 16:9 video or the 9:16 Short, one at a time (docs/decisions.md, 77).
    /// The toggle under the preview is the only control that knows about it; no setting holds one value for
    /// the video and another for the Short.
    var shape: OutputShape { shownShape.flatMap { outputs.contains($0) ? $0 : nil } ?? outputs[0] }

    /// Shows the other shape, for a take made for both. It's saved with the project, so the sidebar's
    /// thumbnail and a duplicate follow it.
    func show(_ shape: OutputShape) {
        guard outputs.contains(shape), shape != self.shape else { return }
        shownShape = shape
        // The frame on screen is the other shape's: let the new one arrive on a clear preview.
        panels = []
        poster = nil
        saveState()
        Task { await reload() }
    }

    /// Choosing a clip inspects it without seeking or interrupting playback.
    func selectClip(_ id: ClipID, mode: ClipPicking.Mode = .replace) {
        let ids = clipPicking.pick(id, mode: mode, selected: selection.clipIDs, ordered: edit?.main.map(\.id) ?? [])
        selection = .clips(ids)
    }

    init(folder: ProjectFolder, alignFix: @escaping FixAligner = EditorModel.align, preferences: UserDefaults = .standard) {
        self.folder = folder
        self.alignFix = alignFix
        self.preferences = preferences
        if let saved = preferences.object(forKey: Self.silenceThresholdKey) as? Double { silenceThreshold = Edit.silenceThreshold(saved) }
        if let state = try? folder.loadEditorState() {
            markIn = state.markIn
            markOut = state.markOut
            markers = state.markers
            currentTime = state.playhead
            shownShape = state.shape
        }
    }

    // MARK: - Watching

    /// Reloads whenever the edit or the project changes on disk, until cancelled.
    func watch() async {
        defer {
            cancelFix(); rescale?.cancel(); posterTask?.cancel(); previewLoad.cancel(); pause(); seeking.cancel()
            framingPreview.cancel()
            loudnessTask?.cancel()
            for read in waveformReads.values { read.task.cancel() }
            waveformReads.removeAll()
            previewLoudness.disable()
            let renderer = loudnessRenderer
            Task { await renderer.clear() }
        }
        await reload()
        var tick = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            let seconds = player.currentTime().seconds
            if seconds.isFinite, seeking.active == nil, isPlaying || player.rate != 0 { currentTime = seconds }
            if isPlaying, !isPreparing, seeking.active == nil, player.timeControlStatus == .paused {
                playback.pause()
                scheduleStateSave()
            }
            tick += 1
            if tick.isMultiple(of: 10) {
                let revision = try? folder.loadEdit().revision
                if revision != watchedRevision || fileDates() != watchedFiles { await reload() }
            }
        }
    }

    func reload() async {
        // A reload can arrive in the middle of a framing drag: cleaning finishes, or an agent saves. The
        // drag keeps its picture and gets it back once the new edit is in place. An audition nobody is
        // holding is dropped, so the saved framing shows.
        let held = auditionsFraming && isPointerDown() ? lastAudition : nil
        if held == nil { cancelTransformPreview() }
        await reloadFromDisk()
        if let held, auditionsFraming {
            previewTransform(picture: held.picture, centerX: held.centerX, centerY: held.centerY, zoom: held.zoom)
        }
    }

    private func reloadFromDisk() async {
        loudnessTask?.cancel()
        let dates = fileDates()
        // A later reload wins: this one stops as soon as it sees another has started.
        let reload = UUID()
        reloadRequest = reload
        mixRequest = reload
        let folder = folder
        // The project is read once, and the three ways of applying it share that reading. Reading it for
        // each would decode the edit's whole history each time, holding the project's lock against the next
        // change. While a mic is cleaned again, the preview keeps its last cleaned voice (docs/decisions.md, 71).
        let loaded = await Task.detached { Result { try EditorSnapshot.load(folder) } }.value
        guard reloadRequest == reload, !Task.isCancelled else { return }
        switch loaded {
        case .success(let snapshot):
            if applyFramingOnly(snapshot, dates: dates) { return }
            if await applyMixOnly(snapshot, reload: reload, dates: dates) { return }
            posterTask?.cancel()
            await rebuild(snapshot, request: previewLoad.begin(), dates: dates)
        case .failure(let error):
            posterTask?.cancel()
            let request = previewLoad.begin()
            watchedRevision = try? folder.loadEdit().revision
            watchedFiles = dates
            failPreview(error, request: request)
        }
    }

    /// Framing changes only the drawing instructions. Keep the same playing item, audio and clock.
    private func applyFramingOnly(_ snapshot: EditorSnapshot, dates: [Date?]) -> Bool {
        guard let previous = playingInputs, let item = player.currentItem, let built = rawComposition,
              case .ready = previewLoad.state else { return false }
        let inputs = snapshot.inputs
        guard inputs.differsOnlyInFraming(from: previous),
              let scale = builtScale, Self.previewScale(pixelHeight: previewPixelHeight, outputs: [shape]) == scale,
              built.panels.map(\.output) == [shape] else { return false }
        var previousEdit = previous.edit
        previousEdit.revision = inputs.edit.revision
        let needsRedraw = inputs.edit != previousEdit
        let redrawn = needsRedraw ? built.reframed(using: inputs) : built
        apply(snapshot, dates: dates)
        timeline = redrawn.timeline
        rawComposition = redrawn
        playingInputs = inputs
        if needsRedraw { installFraming(redrawn, on: item) }
        if previewLoudness.isPreparing, case .ready(let request) = previewLoad.state {
            prepareNormalizedPreview(redrawn, inputs: inputs, load: request)
        }
        return true
    }

    /// Auditions a static crop without writing edit.json or adding an Undo step.
    func previewTransform(picture: Edit.Picture, centerX: Double? = nil, centerY: Double? = nil, zoom: Double? = nil) {
        guard let inputs = playingInputs, let built = rawComposition, let item = player.currentItem else { return }
        let values = clips(with: picture).map { clip in
            (clip.id, transform(of: clip, picture: picture).changing(centerX: centerX, centerY: centerY, zoom: zoom))
        }
        guard !values.isEmpty else { return }
        lastAudition = (picture, centerX, centerY, zoom)
        let staged = inputs.withEdit { edit in
            for (id, value) in values { try? edit.setTransform(value, picture: picture, for: [id]) }
        }
        auditionsFraming = true
        installFraming(built.reframed(using: staged), on: item)
    }

    /// Ends an audition after release. Its last picture remains until the saved edit's instructions arrive.
    func finishTransformPreview() {
        auditionsFraming = false
        lastAudition = nil
        framingPreview.cancel()
    }

    /// Leaving an adjustment without saving restores the persisted framing.
    func cancelTransformPreview() {
        guard auditionsFraming else { return }
        finishTransformPreview()
        if let built = rawComposition, let item = player.currentItem { installFraming(built, on: item) }
    }

    private func installFraming(_ built: BuiltComposition, on item: AVPlayerItem) {
        posterTask?.cancel()
        item.videoComposition = built.videoComposition
        if !isPlaying {
            if let request = seeking.request(currentTime) { performSeek(request) }
            framingPreview.show(built, at: currentTime) { [weak self] image in
                self?.poster = image
            }
        }
    }

    /// A change to levels, or to Cleanup and Voice before the new voice is ready, changes only the mix: the
    /// playing item takes the new mix in place, so playback carries on without the picture flickering. False
    /// when the change needs a new composition.
    private func applyMixOnly(_ snapshot: EditorSnapshot, reload: UUID, dates: [Date?]) async -> Bool {
        guard normalizedAudio == nil, let previous = playingInputs, let previousBuilt = rawComposition,
              let item = player.currentItem, case .ready = previewLoad.state,
              // Switching output needs new picture instructions even when the edit's audio is unchanged.
              previousBuilt.panels.map(\.output) == [shape] else { return false }
        let inputs = snapshot.inputs
        guard inputs.differsOnlyInMix(from: previous),
              // A window that changed size needs a rebuild at the new scale.
              let scale = builtScale, Self.previewScale(pixelHeight: previewPixelHeight, outputs: [shape]) == scale,
              let built = try? await CompositionBuilder.build(inputs, outputs: [shape], scale: scale)
        else { return false }
        // A newer load, or a newer item, wins.
        guard mixRequest == reload, player.currentItem === item, case .ready = previewLoad.state, !Task.isCancelled else { return true }
        installMix(built, snapshot: snapshot, dates: dates, on: item)
        return true
    }

    /// Publishes the new edit and its timeline together while preserving the playing item.
    /// Hit testing and the level line read the timeline's clips, not just the edit's clips.
    func installMix(_ built: BuiltComposition, snapshot: EditorSnapshot, dates: [Date?], on item: AVPlayerItem) {
        let inputs = snapshot.inputs
        apply(snapshot, dates: dates)
        timeline = built.timeline
        item.audioMix = built.audioMix
        playingInputs = inputs
        rawComposition = built
        if case .ready(let request) = previewLoad.state { prepareNormalizedPreview(built, inputs: inputs, load: request) }
    }

    func retryPreview() {
        Task { await reload() }
    }

    private func failPreview(_ error: any Error, request: UUID) {
        loudnessTask?.cancel()
        if previewLoudness.isEnabled {
            let id = previewLoudness.begin()
            previewLoudness.fail(id, message: error.localizedDescription)
        }
        previewLoad.finish(request, outcome: .failed(error.localizedDescription))
        playback.pause()
        seeking.cancel()
        displayReadyItem = nil
        player.replaceCurrentItem(with: nil)
        rawComposition = nil
        normalizedAudio = nil
        timeline = nil
        poster = nil
        panels = []
    }

    /// The previews' height on screen changed, in pixels: rebuilds the preview at the matching scale once
    /// the window stops changing size.
    func previewHeightChanged(toPixels pixels: Double) {
        guard pixels > 0, abs(pixels - previewPixelHeight) > 0.5 else { return }
        previewPixelHeight = pixels
        rescale?.cancel()
        guard let builtScale, Self.previewScale(pixelHeight: pixels, outputs: [shape]) != builtScale else { return }
        rescale = Task {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await reload()
        }
    }

    /// The preview's scale, where 1 is 1080p: the previews' height on screen in pixels, rounded up to a
    /// quarter, from half (before the window is laid out, and for small windows) up to 4K.
    nonisolated static func previewScale(pixelHeight: Double, outputs: [OutputShape]) -> Double {
        // The outputs sit side by side as tall as the shortest (`CompositionBuilder`).
        let shortest = outputs.map { Double($0.height) }.min() ?? Double(OutputShape.landscape.height)
        guard pixelHeight > 0, shortest > 0 else { return 1 }
        return min(2, max(0.5, (pixelHeight / shortest * 4).rounded(.up) / 4))
    }

    /// Publishes the files and the preview from the same load, so timeline actions use matching times.
    private func apply(_ snapshot: EditorSnapshot, dates: [Date?]) {
        let inputs = snapshot.inputs
        project = inputs.project
        edit = inputs.edit
        transcripts = inputs.transcripts
        spellings = inputs.spellings
        history = snapshot.history
        canRedo = snapshot.canRedo
        watchedRevision = inputs.edit.revision
        watchedFiles = dates
        pruneSelection()
        loadScreenAndSound(inputs.project, primaryAudio: inputs.primaryAudio)
        playedWords = PlayedWord.project(edit: inputs.edit, placements: inputs.edit.placements,
                                        transcripts: inputs.transcripts, spellings: inputs.spellings)
        rebuildSnapper()
        rebuildReading()
    }

    func rebuildReading() {
        let next = makeReading()
        guard next != reading else { return }
        reading = next
        readingVersion += 1
    }

    /// When `project.json`, the cleaned voices, the transcripts and the screen's reading last changed.
    private func fileDates() -> [Date?] {
        [folder.projectFileURL, folder.editFileURL, folder.url(for: .audio), folder.url(for: .transcripts), folder.url(for: .screen)].map { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    private func loadScreenAndSound(_ project: Project, primaryAudio: [SourceID: URL]) {
        var stills: [SourceID: [TimeInterval]] = [:]
        // The screen log never changes once recorded, so each source's is read once.
        var fronts = screenFronts
        for source in project.sources {
            if let analysis = try? folder.loadScreenAnalysis(for: source.id) { stills[source.id] = analysis.stills.map(\.start) }
            if fronts[source.id] == nil {
                fronts[source.id] = ScreenFront.settled(from: folder.loadScreenLogEvents(for: source), until: source.duration)
            }
            if let track = source.primaryAudioTrack {
                readWaveform(.voice(source.id), url: primaryAudio[source.id] ?? track.file.url(relativeTo: folder.url), offset: track.startOffset)
            }
            if let track = source.track(.systemAudio) {
                readWaveform(.system(source.id), url: track.file.url(relativeTo: folder.url), offset: track.startOffset)
            }
        }
        stillMoments = stills
        screenFronts = fronts
    }

    private func readWaveform(_ source: WaveformSource, url: URL, offset: Double) {
        if let read = waveformReads[source], read.url == url, read.offset == offset { return }
        waveformReads[source]?.task.cancel()
        let request = UUID()
        let task = Task { [weak self] in
            let reader = Task.detached { await Waveform.load(url, startOffset: offset) }
            let waveform = await withTaskCancellationHandler { await reader.value } onCancel: { reader.cancel() }
            guard let self, !Task.isCancelled, self.waveformReads[source]?.request == request else { return }
            guard let waveform else { self.waveformReads.removeValue(forKey: source); return }
            switch source {
            case .voice(let id): self.waveforms[id] = waveform; self.rebuildSnapper()
            case .system(let id): self.systemWaveforms[id] = waveform
            }
        }
        waveformReads[source] = (url, offset, request, task)
    }

    private func rebuild(_ snapshot: EditorSnapshot, request: UUID, dates: [Date?]) async {
        let inputs = snapshot.inputs
        do {
            // One shape at a time: the one the editor shows, if the take is made for it.
            let made = inputs.project.effectiveFormat.outputs
            let outputs = [shownShape.flatMap { made.contains($0) ? $0 : nil } ?? made[0]]
            let scale = Self.previewScale(pixelHeight: previewPixelHeight, outputs: outputs)
            let built = try await CompositionBuilder.build(inputs, outputs: outputs, scale: scale)
            guard previewLoad.contains(request), !Task.isCancelled else { return }
            let posterComposition = try? built.copyForReading()
            apply(snapshot, dates: dates)
            // The panels hold the frame they show until the new item has one, then the new poster replaces it.
            timeline = built.timeline
            panels = built.panels
            renderSize = built.videoComposition.renderSize
            builtScale = scale
            frameDuration = built.videoComposition.frameDuration.seconds
            mixRequest = nil
            playingInputs = inputs
            rawComposition = built
            replacePlayer(with: built, request: request)
            normalizedAudio = nil
            prepareNormalizedPreview(built, inputs: inputs, load: request)
            problem = nil
            // A poster is only a fallback while the player gets its first picture. Decoding it must
            // never hold the timeline, editing controls or playback hostage to a stalled reader.
            guard let posterComposition else { return }
            let position = currentTime
            let read = Task.detached { try await FrameGrabber.stills(of: posterComposition, at: [position], maximumWidth: 2600) }
            posterTask = Task { [weak self] in
                let still = try? await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
                guard let self, !Task.isCancelled, self.previewLoad.acceptsPoster(for: request) else { return }
                self.poster = still?.first.flatMap { NSImage(data: $0.jpeg) }
            }
        } catch RenderError.emptyEdit {
            guard previewLoad.contains(request), !Task.isCancelled else { return }
            apply(snapshot, dates: dates)
            previewLoad.finish(request, outcome: .empty)
            timeline = nil
            panels = []
            currentTime = 0
            playback.pause()
            poster = nil
            seeking.cancel()
            displayReadyItem = nil
            player.replaceCurrentItem(with: nil)
            rawComposition = nil
            normalizedAudio = nil
            playingInputs = inputs
            if previewLoudness.isEnabled {
                let id = previewLoudness.begin()
                previewLoudness.finish(id, hasAudio: false)
            }
            problem = nil
        } catch {
            guard previewLoad.contains(request), !Task.isCancelled else { return }
            // Publish the attempted edit even when its media fails, so Undo and History can recover it.
            // Remember its revision too: don't repeatedly rebuild unchanged missing media every 500 ms.
            apply(snapshot, dates: dates)
            failPreview(error, request: request)
        }
    }

    /// Installs either the raw or mastered composition without changing playback intent or position.
    private func replacePlayer(with built: BuiltComposition, request: UUID) {
        let playingTime = player.currentTime().seconds
        let latestTime = seeking.target ?? (isPlaying && playingTime.isFinite ? playingTime : currentTime)
        let position = min(max(0, latestTime), max(0, built.timeline.duration - frameDuration))
        previewLoad.installed(request)
        displayReadyItem = nil
        seeking.cancel()
        let item = built.makePlayerItem()
        FrameHold.attach(to: item)
        frameHold.capture(from: player.currentItem)
        player.replaceCurrentItem(with: item)
        if let seek = seeking.request(position) { performSeek(seek) }
        currentTime = position
        player.rate = playback.rate
        scheduleStateSave()
    }

    private func setNormalizePreview(_ enabled: Bool) {
        guard enabled != previewLoudness.isEnabled else { return }
        if enabled {
            _ = previewLoudness.begin()
            retryNormalizedPreview()
        } else {
            loudnessTask?.cancel()
            previewLoudness.disable()
            if normalizedAudio != nil, let rawComposition {
                switch previewLoad.state {
                case .ready(let load), .seeking(let load): replacePlayer(with: rawComposition, request: load)
                default: break // A newer picture is already being built and will install raw sound.
                }
                normalizedAudio = nil
            }
        }
    }

    func retryNormalizedPreview() {
        guard previewLoudness.isEnabled else { return }
        switch previewLoad.state {
        case .empty:
            let request = previewLoudness.begin()
            previewLoudness.finish(request, hasAudio: false)
            return
        case .failed(let message):
            let request = previewLoudness.begin()
            previewLoudness.fail(request, message: message)
            return
        default: break
        }
        guard let rawComposition, let inputs = playingInputs else { return }
        let load: UUID
        switch previewLoad.state {
        case .ready(let id), .seeking(let id): load = id
        default: return
        }
        prepareNormalizedPreview(rawComposition, inputs: inputs, load: load)
    }

    private func prepareNormalizedPreview(_ built: BuiltComposition, inputs: RenderInputs, load: UUID) {
        guard previewLoudness.isEnabled else { return }
        loudnessTask?.cancel()
        let request = previewLoudness.begin()
        let renderer = loudnessRenderer
        let target = inputs.edit.audio.loudnessTarget, ceiling = inputs.edit.audio.truePeakCeiling
        loudnessTask = Task { [weak self] in
            do {
                let independent = try built.copyForReading()
                let key = try PreviewSoundKey.make(for: independent, target: target, ceiling: ceiling)
                let audio = try await renderer.audio(for: key, of: independent) { samples, rate in
                    try LoudnessStage.process(AudioSamples(samples: samples, sampleRate: rate), target: target, ceiling: ceiling,
                                              checkpoint: { try Task.checkCancellation() }).audio.samples
                }
                try Task.checkCancellation()
                let normalized: BuiltComposition?
                if let audio { normalized = try await MasteredSound.replacingSound(in: independent, with: audio.url) }
                else { normalized = nil }
                try Task.checkCancellation()
                guard let self, self.previewLoudness.contains(request), self.previewLoad.acceptsPoster(for: load) else { return }
                if let normalized {
                    self.replacePlayer(with: normalized, request: load)
                    self.normalizedAudio = audio
                }
                self.previewLoudness.finish(request, hasAudio: audio != nil)
            } catch is CancellationError { }
            catch {
                guard let self else { return }
                self.previewLoudness.fail(request, message: error.localizedDescription)
            }
        }
    }

    /// Drops selected things that a change took away.
    private func pruneSelection() {
        guard let edit else { return }
        isPruningSelection = true
        defer { isPruningSelection = false }
        selection = selection.retaining(in: edit)
    }

    // MARK: - Playback

    func togglePlayback() {
        // The old item keeps playing while an edit's preview rebuilds; the new one takes over at its time.
        guard timeline != nil else { return }
        if isPlaying {
            pause()
        } else {
            if currentTime >= duration - 0.05 { seek(to: 0) }
            playback.play()
            player.rate = playback.rate
        }
    }

    func pause() {
        player.pause()
        playback.pause()
        if seeking.active == nil, player.currentTime().seconds.isFinite { currentTime = player.currentTime().seconds }
        scheduleStateSave()
    }

    /// J and L: back and forward, faster with each press. K stops.
    func shuttle(_ direction: Int) {
        if direction == 0 { return pause() }
        guard timeline != nil else { return }
        playback.shuttle(direction > 0 ? .forward : .backward)
        player.rate = playback.rate
    }

    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, timeline != nil else { return }
        let time = min(max(0, seconds), max(0, duration - frameDuration))
        currentTime = time
        seekRequest += 1
        if let request = seeking.request(time) { performSeek(request) }
        scheduleStateSave()
    }

    /// One exact seek runs at a time, followed only by the latest requested target. Completion tokens
    /// keep a replaced item's callback from changing the new preview's readiness or playback intent.
    private func performSeek(_ request: PreviewSeeking.Request) {
        player.seek(to: CMTime(seconds: request.time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch self.seeking.completed(request) {
                case .stale: break
                case .next(let next): self.performSeek(next)
                case .settled:
                    if case .seeking(let load) = self.previewLoad.state {
                        self.previewLoad.finish(load, outcome: .ready)
                        self.displayReadyItem = self.player.currentItem
                    }
                    self.player.rate = self.playback.rate
                }
            }
        }
    }

    func step(frames: Int) {
        if isPlaying { pause() }
        seek(to: currentTime + Double(frames) * frameDuration)
    }

    /// The cuts and the ends, for ↑ and ↓.
    var editPoints: [TimeInterval] {
        guard let timeline else { return [] }
        return Array(Set(timeline.clips.flatMap { [$0.timeline.start, $0.timeline.end] })).sorted()
    }

    func jumpToEdit(forward: Bool) {
        let points = editPoints
        let target = forward ? points.first { $0 > currentTime + 0.001 } : points.last { $0 < currentTime - 0.001 }
        if let target { seek(to: target) }
    }

    // MARK: - Snapping

    /// Snap points from the silences and still moments, and dips from each voice's waveform
    /// (docs/decisions.md, 74). Rebuilt when a waveform finishes loading.
    func rebuildSnapper() {
        snapper = EditSnapper(transcripts: transcripts, stillMoments: stillMoments, envelopes: waveforms.mapValues(\.envelope))
    }

    /// A timeline time with snapping applied, if it's on, and what it stuck to.
    func snapped(_ time: TimeInterval, tolerance: TimeInterval) -> (time: TimeInterval, target: EditSnapper.Target?) {
        if snapping, let edit {
            let snapped = snapper.snap(time, in: edit, tolerance: tolerance, extra: [currentTime])
            if snapped.target != nil { return snapped }
        }
        return (Timecode(frameDuration: frameDuration).frameTime(nearest: time), nil)
    }

    // MARK: - Editor state

    /// Saves the playhead and the selection for `get_editor_state` (docs/decisions.md, 57), a moment after
    /// they stop changing. Not while playing: the playhead is saved when it stops.
    private func scheduleStateSave() {
        stateSave?.cancel()
        stateSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            saveState()
        }
    }

    /// Saves where the editor is now, with the shape it shows.
    private func saveState() {
        let state = EditorState(
            playhead: currentTime,
            selection: selection.persisted,
            markIn: markIn,
            markOut: markOut,
            markers: markers,
            shape: shownShape,
            editRevision: edit?.revision ?? 0
        )
        try? folder.saveEditorState(state)
    }

    // MARK: - Changes

    /// Makes one change to the edit as the creator, the same way Claude's tools do, and reloads.
    @discardableResult
    func change(_ reason: String, _ body: (inout Edit, TranscriptIndex) throws -> Void) -> Bool {
        do {
            var previousRevision: Int?
            let saved = try folder.updateEdit(author: .app, reason: reason) { edit, transcripts in
                previousRevision = edit.revision
                try body(&edit, transcripts)
            }
            problem = nil
            notice = nil
            if saved.revision != previousRevision { Task { await reload() } }
            return true
        } catch {
            problem = error.localizedDescription
            NSSound.beep()
            return false
        }
    }

    func undo() {
        cancelFix()
        do {
            try folder.undo()
            Task { await reload() }
        } catch {
            problem = error.localizedDescription
        }
    }

    func redo() {
        cancelFix()
        do {
            try folder.redo(author: .app)
            Task { await reload() }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Puts the edit back as it was before a change and everything after it.
    func undo(through sequence: Int) {
        cancelFix()
        do {
            try folder.undo(through: sequence)
            Task { await reload() }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// A first cut for a fresh recording: the whole transcript as one clip.
    /// Puts a whole source back on the timeline, as one clip.
    func addWholeSource(_ source: SourceID) {
        guard let info = project?.source(source) else { return }
        change("Put all of \(info.name) on the timeline") { edit, _ in
            edit.addWholeSource(info)
        }
    }

    func sourceDuration(of clip: ClipID) -> TimeInterval? {
        guard let source = edit?.main.first(where: { $0.id == clip })?.source else { return nil }
        return project?.source(source)?.duration
    }

    /// The selected clip, when exactly one is.
    var selectedClip: Clip? {
        guard selection.clipIDs.count == 1, let id = selection.clipIDs.first else { return nil }
        return edit?.main.first { $0.id == id }
    }

    /// Selected clips in timeline order, including an explicitly selected clip edge.
    var selectedClips: [Clip] { edit?.main.filter { selection.clipIDs.contains($0.id) } ?? [] }

    /// Shared attributes are shown only when every selected clip agrees.
    func sharedClipValue<Value: Equatable>(_ value: (Clip) -> Value) -> Value? {
        let values = selectedClips.map(value)
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    func inspectProject() {
        selection = .none
        inspectorTab = .video
    }

    var selectedOverlay: Overlay? {
        guard selection.overlayIDs.count == 1, let id = selection.overlayIDs.first else { return nil }
        return edit?.overlays.first { $0.id == id }
    }

    var selectedFreeze: Freeze? {
        guard let id = selection.freezeID else { return nil }
        return edit?.freezes.first { $0.id == id }
    }

    /// The marked range (I and O), once both are set.
    var markedRange: TimeRange? {
        guard let markIn, let markOut, markOut > markIn else { return nil }
        return TimeRange(start: markIn, end: markOut)
    }

    /// The stretch ⇧H holds and Delete removes when no clip is selected: the marked range.
    var selectedRange: TimeRange? {
        if let words = selection.wordRange, let range = timelineRange(of: words) { return range }
        return selection.isEmpty ? markedRange : nil
    }

    /// Where a run of words plays on the timeline, first to last.
    func timelineRange(of words: ItemRange) -> TimeRange? {
        guard let edit, let transcript = try? transcripts.transcript(containing: words),
            let time = try? CutPointSnapper(transcript: transcript).timeRange(for: words)
        else { return nil }
        let pieces = edit.timelinePieces(of: time, in: transcript.source)
        guard let first = pieces.first, let last = pieces.last else { return nil }
        return TimeRange(start: first.timeline.start, end: last.timeline.end)
    }

    func clear(_ message: String? = nil) {
        problem = message
    }
}

#if DEBUG
extension EditorModel {
    /// Loads the project without the player, for Xcode's previews, which don't wait for the async load.
    func loadForPreview(playhead: TimeInterval = 0, selecting clip: ClipID? = nil) {
        guard let inputs = try? RenderInputs.load(folder) else { return }
        project = inputs.project
        edit = inputs.edit
        transcripts = inputs.transcripts
        spellings = inputs.spellings
        history = (try? folder.history.entries()) ?? []
        timeline = EditTimeline(edit: inputs.edit, transcripts: inputs.transcripts)
        var x = 0.0
        panels = [shownShape.flatMap { inputs.project.effectiveFormat.outputs.contains($0) ? $0 : nil } ?? inputs.project.effectiveFormat.outputs[0]].map { output in
            let width = Double(output.width) * 540 / Double(output.height == 1920 ? 1920 : 1080) * (output == .vertical ? 1 : 1)
            defer { x += width }
            return (output, CGRect(x: x, y: 0, width: width, height: 540))
        }
        for source in inputs.project.sources {
            if let analysis = try? folder.loadScreenAnalysis(for: source.id) { stillMoments[source.id] = analysis.stills.map(\.start) }
        }
        playedWords = PlayedWord.project(edit: inputs.edit, placements: timeline?.clips ?? [],
                                        transcripts: inputs.transcripts, spellings: inputs.spellings)
        rebuildSnapper()
        loadScreenAndSound(inputs.project, primaryAudio: inputs.primaryAudio)
        rebuildReading()
        currentTime = playhead
        let request = previewLoad.begin()
        previewLoad.finish(request, outcome: .ready)
        if let clip { selection = .clips([clip]) }
        zoom = 80
    }
}
#endif

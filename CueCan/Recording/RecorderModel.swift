import AppKit
import AVFoundation
import Foundation
import Observation
import ProjectKit
import RecorderKit
import RenderKit

/// A recording from setting up to Stop (docs/ui.md, R1 to R6 and R9): the setup bar, the capture area and
/// the Recording Panel, the camera and the mic, live from the moment the bar opens, and the recording. The
/// screen is a source like the camera and the mic: with No screen, the camera is recorded alone.
@Observable
final class RecorderModel {
    /// Where the recording is, for the views. It's derived from ``state``, which also holds what each stage owns.
    typealias Phase = RecordingPhase

    /// One recording under way: everything that exists only while it records, together, with the format
    /// and the area it started with.
    private struct Take {
        let attemptID: UUID
        /// Nil for a recording of the camera alone.
        let screen: ScreenCapture?
        let session: RecordingSession
        let project: ProjectFolder
        let format: VideoFormat
        /// The camera's framing in each slot when the take started, saved into its edit on Stop as the
        /// editor's starting framing (docs/decisions.md, 52).
        let framings: CameraFramings
        /// The look the take starts with (docs/decisions.md, 66).
        let look: OutputLook
        /// What happens on screen, for a take with a screen (docs/decisions.md, 58).
        let screenLog: ScreenActivityLogger?
        /// A camera was on when the take started.
        let recordsCamera: Bool
    }

    /// The recording's state, holding what each stage needs, so a recording can't exist without its take.
    private enum State {
        case idle
        case settingUp
        /// Starting: the screen capture is starting up, in the task that then starts the take.
        case starting(id: UUID, task: Task<Void, Never>, stopped: String? = nil)
        case recording(Take)
        case paused(Take)
        case saving
        case discarding

        var phase: Phase {
            switch self {
            case .idle: .idle
            case .settingUp: .settingUp
            case .starting: .starting
            case .recording: .recording
            case .paused: .paused
            case .saving: .saving
            case .discarding: .discarding
            }
        }

        var take: Take? {
            switch self {
            case .recording(let take), .paused(let take): take
            default: nil
            }
        }
    }

    /// Device readiness belongs to one setup. Closing it invalidates pending permission responses.
    private enum DevicePreparation {
        case idle
        case preparing(id: UUID, task: Task<Void, Never>)
        case ready
    }

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored let camera = CameraCapture()
    @ObservationIgnored private(set) lazy var cameraPreview = CameraPreviewFeed(camera: camera)
    @ObservationIgnored let mic = MicCapture()
    @ObservationIgnored private var state = State.idle {
        didSet { if phase != state.phase { phase = state.phase } }
    }
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Checks while setting up that the camera is sending a picture, and starts it again when it isn't.
    @ObservationIgnored private var cameraWatcher: Task<Void, Never>?
    private var frameWatch: CameraFrameWatch?
    private var preparation = DevicePreparation.idle
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private(set) lazy var area = CaptureAreaController(recorder: self)
    /// While setting up, the one element: the live preview over the strip (docs/decisions.md, 79).
    @ObservationIgnored private(set) lazy var element = SetupElementController(recorder: self)
    @ObservationIgnored private(set) lazy var panel = RecordingPanelController(recorder: self)
    @ObservationIgnored private(set) lazy var preview = ScreenPreviewFeed(recorder: self)

    private(set) var cameras: [CaptureDevice] = []
    private(set) var microphones: [CaptureDevice] = []
    /// The camera, or nil for none.
    private(set) var cameraID: String?
    /// The mic, or nil for none.
    private(set) var micID: String?
    /// Whether a screen is recorded, or No screen, for the camera alone (docs/ui.md, R9). Remembered, like
    /// the camera and the mic. Which screen is ``CaptureAreaController/selectedDisplayID``.
    private(set) var recordsScreen = !UserDefaults.standard.bool(forKey: "screenDisabled") {
        didSet { UserDefaults.standard.set(!recordsScreen, forKey: "screenDisabled") }
    }
    /// System audio is recorded with the screen, through ScreenCaptureKit, so with No screen there's none.
    /// (Recording it alone, through a Core Audio tap, is VERIFY: docs/ui.md, R9.)
    var capturesSystemAudio: Bool { recordsScreen && recordsSystemAudio }
    var recordsSystemAudio = UserDefaults.standard.object(forKey: "recordsSystemAudio") as? Bool ?? true {
        didSet { UserDefaults.standard.set(recordsSystemAudio, forKey: "recordsSystemAudio") }
    }

    /// Where the recording will be posted. A setup opens on the last one used; nil only before the first
    /// is ever picked (docs/decisions.md, 78).
    private(set) var destination: VideoFormat.Destination?
    /// The format last used and the layout last picked for each, remembered between setups
    /// (docs/decisions.md, 66 and 78).
    private(set) var memory = RecorderModel.savedMemory {
        didSet {
            if let data = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(data, forKey: Self.memoryKey) }
        }
    }
    /// The chosen format, once a destination is picked.
    var format: VideoFormat? { destination.map { VideoFormat(destination: $0, layout: memory.layout(for: $0)) } }
    /// The look the take will start with: the last project's, with the side toggles from the layout menu
    /// (docs/decisions.md, 66). The menu's pictures, the shading and the panel's preview are drawn in it.
    private(set) var look = OutputLook.plain
    /// What the setup element's well shows: the live preview, the Layout choices or framing, each in the
    /// preview's place, so the element never changes size (docs/ui.md, R10). One at a time.
    var well = SetupWell.preview
    /// The Layout choices are showing in the well.
    var isChoosingLayout: Bool { well == .choices }

    /// What the panel and the menu bar call the format: "Both · Split", or "Both · camera only" with no
    /// screen, where the layout means nothing.
    var formatLabel: String {
        guard let format else { return "No format chosen" }
        return recordsScreen ? format.label : format.cameraOnlyLabel
    }

    /// How the camera is framed for the next take, in each kind of slot (docs/decisions.md, 52): what was
    /// framed by hand for this camera, remembered since each sits differently, and the face found while
    /// setting up in every other slot (78). A take's edit gets it when the take is saved, as the editor's
    /// starting framing, and it can change after.
    var framings: CameraFramings {
        faceFraming.map { framedByHand.filling(with: $0) } ?? framedByHand
    }
    /// The slots framed by hand for this camera, remembered.
    private var framedByHand = CameraFramings()
    /// Whether a slot has a framing by hand, which Reset forgets.
    func isFramedByHand(_ slot: CameraSlot) -> Bool { framedByHand[slot] != nil }
    /// The creator's face, found once when the camera starts while setting up. It's never remembered and
    /// never followed while recording, so it's found again next time.
    private var faceFraming: CameraFraming?
    @ObservationIgnored private var faceFinder: Task<Void, Never>?
    private(set) var cameraPictureSize = CGSize(width: 1920, height: 1080)
    /// The framing popover is open.
    /// Framing is showing in the well, and on which slot.
    var framingSlot: CameraSlot? {
        if case .framing(let slot) = well { slot } else { nil }
    }
    /// Why the strip's framing circle is dimmed, or nil when there's a camera to frame.
    var framingBlocker: String? {
        SetupWellLayout.framingBlocker(hasFormat: format != nil, cameraOn: isCameraOn, cameraHasPicture: cameraHasPicture)
    }

    /// What the level meter shows, in dBFS: quick to rise, slow to fall, so it doesn't strobe. It's drawn
    /// from the same buffers that are written to the mic file, and it's the panel's check that sound is
    /// coming in; there's no waveform (docs/decisions.md, 18).
    private(set) var meterDecibels: Float = -120
    /// The meter's held peak, in dBFS: it stays a moment, so a clip can be seen.
    private(set) var meterPeakDecibels: Float = -120
    @ObservationIgnored private var ballistics = LevelBallistics()
    /// The mic that disappeared, until another is chosen. The app never switches silently to another.
    private(set) var lostMic: CaptureDevice?

    /// Where the recording is. Set only through ``state``.
    private(set) var phase = Phase.idle
    /// The camera and the mic are still being asked for and chosen, so Start waits.
    var isPreparingDevices: Bool {
        if case .preparing = preparation { return true }
        return false
    }
    private(set) var elapsed: TimeInterval = 0
    var problem: String?
    private var cameraReadiness = DeviceReadiness()
    private var micReadiness = DeviceReadiness()
    private(set) var cameraAllowed = true
    private(set) var micAllowed = true

    init(app: AppModel) {
        self.app = app
    }

    var micName: String? { microphones.first { $0.id == micID }?.name }
    var cameraName: String? { cameras.first { $0.id == cameraID }?.name }
    /// Read from ``phase``, which views observe; ``state`` itself isn't observed.
    var isRecording: Bool { phase.isRecording }
    /// Whether the setup bar, a start or a recording is under way, when the menu bar's menu shows the
    /// status and the controls instead of the recording commands (docs/ui.md, R1).
    var isActive: Bool { phase != .idle }
    var isCameraOn: Bool { cameraReadiness.isReady }
    /// The chosen camera is sending frames (``CameraFrameWatch``). Start recording waits for it.
    var cameraHasPicture: Bool { frameWatch?.hasPicture == true }
    /// Camera-frame failures belong to the current watch. Retrying or changing the camera replaces
    /// that watch, so a recovered camera cannot keep displaying its previous failure.
    var setupProblem: String? {
        if frameWatch?.state == .failed {
            return "\(cameraName ?? "The camera") isn’t sending a picture. Choose it again."
        }
        return problem
    }
    var isMicOn: Bool { micReadiness.isReady }

    /// What the panel's controls can do now (docs/decisions.md, 51). They follow the recording's state,
    /// so the panel and the menu bar's menu agree.
    var canPause: Bool { isRecording }
    var canDiscard: Bool { isRecording }
    var canStop: Bool { isRecording }

    /// Whether Start recording works now, and if not, why: shown on the dimmed buttons.
    var startConditions: StartConditions {
        StartConditions(isSettingUp: phase == .settingUp, hasFormat: format != nil, recordsScreen: recordsScreen,
                        hasArea: area.placement != nil, hasCamera: isCameraOn, devicesReady: !isPreparingDevices && !cameraReadiness.isPreparing && !micReadiness.isPreparing,
                        cameraHasPicture: cameraHasPicture)
    }

    // MARK: - Setting up

    /// Opens the setup element on the format used last, so a second recording is one shortcut and Return
    /// (docs/decisions.md, 78 and 79). On the first setup ever, no format is chosen. The Recording Panel
    /// shows only once the take starts.
    func openSetup() {
        switch phase {
        case .idle:
            // An ended beta records nothing new; what's recorded still opens (docs/decisions.md, 98).
            if app?.stopsForEndedBeta() == true { return }
            state = .settingUp
            problem = nil
            well = .preview
            destination = memory.destination
            look = app?.library.lastLook() ?? .plain
            installKeyMonitor()
            prepareDevices()
            // The display the creator is working on, until they pick another in the Screen picker.
            area.selectDisplayUnderPointer()
            // The area first, so the element's first place can keep out of it.
            formatChanged()
            element.show()
            element.focus()
        case .settingUp:
            element.focus()
        default:
            break
        }
    }

    /// Closes the element and the area. Snapped windows stay where they are.
    func closeSetup() {
        guard phase == .settingUp else { return }
        endSetup()
    }

    /// Picks where the recording will be posted, and remembers it for the next setup. Picking the chosen one
    /// again does nothing (docs/decisions.md, 78; Claude's proposal, AUTHOR'S TAKE NEEDED).
    func choose(_ destination: VideoFormat.Destination) {
        guard phase == .settingUp, destination != self.destination else { return }
        self.destination = destination
        memory.use(destination)
        formatChanged()
    }

    /// Picks a layout for the chosen format (docs/decisions.md, 89). Side by side's share sets the shape of the
    /// area; a card records the whole frame, and its settings only change what the area shades.
    func choose(_ layout: TakeLayout) {
        // With no screen the camera fills the frame, so the layout means nothing.
        guard phase == .settingUp, recordsScreen, let destination, let current = format?.layout else { return }
        let layout = layout.card.map { TakeLayout.card($0.fitted(to: destination)) } ?? layout
        guard layout.isOffered(for: destination), layout != current else { return }
        memory.use(layout, for: destination)
        if layout.captureRatio(for: destination) != current.captureRatio(for: destination) {
            formatChanged()
        } else {
            area.coverChanged()
            preview.areaChanged()
        }
    }

    /// Switches to Side by side, at the share last picked for this format.
    func chooseSideBySide() {
        guard let destination else { return }
        choose(memory.sideBySide(for: destination))
    }

    /// Switches to Card, as it was last set up for this format.
    func chooseCard() {
        guard let destination else { return }
        choose(.card(memory.card(for: destination)))
    }

    /// The card the Layout choices show: the chosen one, or the one Card would bring back.
    var setupCard: Card {
        format?.layout.card ?? destination.map { memory.card(for: $0) } ?? .standard
    }

    /// Changes the card: its position, size, shape, screen or roundness.
    func changeCard(_ change: (inout Card) -> Void) {
        var card = setupCard
        change(&card)
        choose(.card(card))
    }

    /// Puts Side by side's camera on a side: left or right in the video, above or below in the Short, one side
    /// for both (docs/decisions.md, 77). The take starts with it.
    func chooseSide(_ side: OutputLook.CameraSide) {
        guard phase == .settingUp, side != look.cameraSide else { return }
        look.cameraSide = side
        area.coverChanged()
        preview.areaChanged()
    }

    private static let memoryKey = "setupMemory"

    private static var savedMemory: SetupMemory {
        UserDefaults.standard.data(forKey: memoryKey).flatMap { try? JSONDecoder().decode(SetupMemory.self, from: $0) } ?? SetupMemory()
    }

    /// Picks the screen to record, or nil for No screen (docs/ui.md, R9). A screen brings the area back on
    /// that display, if a format is chosen; No screen takes the area, the dimming and snapping away.
    func chooseScreen(_ displayID: CGDirectDisplayID?) {
        guard phase == .settingUp else { return }
        if let displayID {
            let wasOff = !recordsScreen
            recordsScreen = true
            area.chooseDisplay(displayID)
            // Ask as soon as a screen is wanted, not at Record: macOS lists CueCan under Screen & System Audio
            // Recording only once it has asked, and asking at Record costs the take.
            if !ScreenCapture.hasPermission { ScreenCapture.requestPermission() }
            if wasOff { formatChanged() }
        } else {
            guard recordsScreen else { return }
            recordsScreen = false
            area.hide()
            preview.areaChanged()
        }
    }

    private func formatChanged() {
        guard let format, recordsScreen else { return }
        area.show(ratio: format.captureRatio)
        preview.areaChanged()
    }

    /// Esc: closes the Layout menu if it's open, otherwise everything: the element and the area, and while
    /// a take is starting the take too, with nothing saved. It never stops a recording (docs/decisions.md, 49, 78
    /// and 79).
    func escape() {
        if phase == .settingUp, well != .preview {
            well = .preview
            return
        }
        switch phase {
        case .settingUp:
            closeSetup()
        case .starting:
            cancelStart()
        default:
            break
        }
    }

    /// Esc and Return reach the setup while one of its panels has the keyboard. An open popover takes its
    /// own Esc first.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window is OverlayPanel, !TransientPanel.owns(event.window) else { return event }
            switch event.keyCode {
            case 53: // Esc
                guard self.phase == .settingUp || self.phase == .starting else { return event }
                self.escape()
                return nil
            case 36, 76: // Return, Enter
                guard self.startConditions.canStart else { return event }
                self.startRecording()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Devices

    /// Asks for the camera and the mic and starts them for the panel's previews. Start recording waits
    /// until it's done.
    private func prepareDevices() {
        let attempt = UUID()
        preparation = .preparing(id: attempt, task: Task { [weak self] in
            await self?.wake(attempt: attempt)
            guard let self, self.isPreparing(attempt) else { return }
            self.preparation = .ready
        })
    }

    private func isPreparing(_ attempt: UUID) -> Bool {
        guard case .preparing(let current, _) = preparation else { return false }
        return current == attempt
    }

    private func wake(attempt: UUID) async {
        guard isPreparing(attempt) else { return }
        cameras = CaptureDevices.cameras
        microphones = CaptureDevices.microphones
        cameraReadiness.requestPermission()
        micReadiness.requestPermission()
        let cameraAllowed = await CaptureDevices.requestAccess(for: .video)
        guard isPreparing(attempt) else { return }
        let micAllowed = await CaptureDevices.requestAccess(for: .audio)
        // A setup that was closed, or closed and opened again, while the prompts were up.
        guard isPreparing(attempt) else { return }
        self.cameraAllowed = cameraAllowed
        self.micAllowed = micAllowed
        let defaults = UserDefaults.standard
        let savedCamera = defaults.bool(forKey: "cameraDisabled") ? nil : defaults.string(forKey: "cameraID").flatMap { id in cameras.first { $0.id == id }?.id }
            ?? CaptureDevices.defaultCamera?.id ?? cameras.first?.id
        let savedMic = defaults.bool(forKey: "micDisabled") ? nil : defaults.string(forKey: "micID").flatMap { id in microphones.first { $0.id == id }?.id }
            ?? CaptureDevices.defaultMicrophone?.id ?? microphones.first?.id
        mic.onLevels = { [weak self] levels in
            Task { @MainActor in self?.receive(levels) }
        }
        mic.onDisconnect = { [weak self] device in
            Task { @MainActor in self?.micDisappeared(device) }
        }
        cameraID = savedCamera
        micID = savedMic
        useCamera()
        useMic()
    }

    /// Stops the camera and the mic when nothing shows them, so their lights go off.
    private func sleep() {
        stopWatchingCamera()
        faceFinder?.cancel()
        faceFinder = nil
        cameraReadiness.stop()
        micReadiness.stop()
        camera.stop()
        mic.stop()
        ballistics.reset()
        meterDecibels = -120
        meterPeakDecibels = -120
    }

    /// Frames one kind of camera slot, and remembers it for this camera. The others stay as they are.
    func setFraming(_ framing: CameraFraming, slot: CameraSlot) {
        framedByHand[slot] = framing
        guard let cameraID else { return }
        var saved = Self.savedFramings
        saved[cameraID] = framedByHand.isEmpty ? nil : framedByHand
        Self.savedFramings = saved
    }

    /// Reset, while setting up: forgets the slot's framing by hand, so it's centred on the face again, or
    /// in the middle with no face found (docs/decisions.md, 78; Claude's call, AUTHOR'S TAKE NEEDED).
    func resetFraming(slot: CameraSlot) {
        framedByHand[slot] = nil
        guard let cameraID else { return }
        var saved = Self.savedFramings
        saved[cameraID] = framedByHand.isEmpty ? nil : framedByHand
        Self.savedFramings = saved
    }

    /// Framings given by hand, by camera.
    private static var savedFramings: [String: CameraFramings] {
        get {
            UserDefaults.standard.data(forKey: "cameraFramings").flatMap { try? JSONDecoder().decode([String: CameraFramings].self, from: $0) } ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "cameraFramings") }
        }
    }

    func chooseCamera(_ id: String?) {
        guard phase == .settingUp, !isPreparingDevices else { return }
        cameraID = id
        useCamera()
    }

    func chooseMic(_ id: String?) {
        guard phase == .settingUp, !isPreparingDevices else { return }
        micID = id
        useMic()
    }

    private func useCamera() {
        guard phase != .idle else { return }
        if framingSlot != nil { well = .preview }
        framedByHand = cameraID.flatMap { Self.savedFramings[$0] } ?? CameraFramings()
        faceFinder?.cancel()
        faceFraming = nil
        UserDefaults.standard.set(cameraID == nil, forKey: "cameraDisabled")
        guard let id = cameraID, cameraAllowed, let device = cameras.first(where: { $0.id == id }) else {
            cameraReadiness.stop()
            camera.stop()
            stopWatchingCamera()
            return
        }
        UserDefaults.standard.set(id, forKey: "cameraID")
        stopWatchingCamera()
        let attempt = cameraReadiness.start(device)
        Task {
            do {
                guard cameraReadiness.contains(attempt) else { return }
                try await camera.use(device)
                guard cameraReadiness.finish(attempt, problem: nil) else { return }
                cameraPictureSize = camera.pictureSize
                frameWatch = CameraFrameWatch(startedAt: ProcessInfo.processInfo.systemUptime)
                watchCamera()
                findFace(cameraID: id)
            } catch {
                if cameraReadiness.finish(attempt, problem: error.localizedDescription) { problem = error.localizedDescription }
            }
        }
    }

    /// While setting up, checks twice a second that the camera is sending frames. A camera that's running but
    /// sending nothing is started again, and after two tries the creator is told (docs/ui.md, L1, "Built").
    private func watchCamera() {
        cameraWatcher?.cancel()
        cameraWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled, self.phase == .settingUp, self.isCameraOn, var watch = self.frameWatch else { continue }
                let now = ProcessInfo.processInfo.systemUptime
                let verdict = watch.check(lastFrame: self.camera.lastFrameTime, now: now)
                if self.frameWatch != watch { self.frameWatch = watch }
                switch verdict {
                case .delivering, .waiting:
                    break
                case .restart(let request):
                    NSLog("CueCan: %@ is running but sending no picture; starting it again.", self.cameraName ?? "The camera")
                    await self.camera.restart()
                    guard !Task.isCancelled else { return }
                    self.frameWatch?.restartFinished(request, at: ProcessInfo.processInfo.systemUptime)
                case .failed:
                    return
                }
            }
        }
    }

    /// Finds the creator's face once, as the camera starts while setting up, and centres every slot not
    /// framed by hand on it (docs/decisions.md, 78; Claude's proposal for when, AUTHOR'S TAKE NEEDED). It waits
    /// a moment for the camera's exposure to settle, then takes the middle of a few pictures, so a blink or a
    /// turn doesn't decide it. With no face found, the camera stays centred.
    private func findFace(cameraID: String) {
        faceFinder?.cancel()
        faceFinder = Task { [weak self, camera] in
            try? await Task.sleep(for: .seconds(1))
            var faces: [FaceLocator.Face] = []
            for _ in 0..<3 {
                guard !Task.isCancelled else { return }
                guard let picture = await camera.nextPicture() else { break }
                let face = await Task.detached(priority: .userInitiated) { try? FaceLocator.largestFace(in: picture) }.value
                if let face { faces.append(face) }
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let self, !Task.isCancelled, self.phase == .settingUp, self.cameraID == cameraID else { return }
            guard let face = FaceLocator.median(of: faces) else {
                NSLog("CueCan: found no face in %@, so it stays centred.", self.cameraName ?? "the camera")
                return
            }
            NSLog("CueCan: centred %@ on the face at %.2f, %.2f.", self.cameraName ?? "the camera", face.center.x, face.center.y)
            self.faceFraming = CameraFraming(centerX: face.center.x, centerY: face.center.y, zoom: 1)
        }
    }

    private func stopWatchingCamera() {
        cameraWatcher?.cancel()
        cameraWatcher = nil
        frameWatch = nil
    }

    private func useMic() {
        guard phase != .idle else { return }
        UserDefaults.standard.set(micID == nil, forKey: "micDisabled")
        lostMic = nil
        ballistics.reset()
        meterDecibels = -120
        meterPeakDecibels = -120
        guard let id = micID, micAllowed, let device = microphones.first(where: { $0.id == id }) else {
            micReadiness.stop()
            mic.stop()
            return
        }
        UserDefaults.standard.set(id, forKey: "micID")
        let attempt = micReadiness.start(device)
        Task {
            do {
                guard micReadiness.contains(attempt) else { return }
                try await mic.use(device)
                micReadiness.finish(attempt, problem: nil)
            } catch {
                if micReadiness.finish(attempt, problem: error.localizedDescription) { problem = error.localizedDescription }
            }
        }
    }

    private func receive(_ levels: [LevelSample]) {
        guard phase != .idle else { return }
        meterDecibels = ballistics.observe(levels)
        meterPeakDecibels = ballistics.peakDecibels
    }

    private func micDisappeared(_ device: CaptureDevice) {
        guard micID == device.id, phase != .idle else { return }
        micReadiness.disconnected(device)
        lostMic = device
        state.take?.session.micWasLost()
        // While recording, the take stops here rather than going on without its sound.
        state.take?.session.trackFailed(.microphone, reason: "\(device.name) disconnected")
        microphones = CaptureDevices.microphones
        problem = "\(device.name) disconnected."
    }

    // MARK: - Recording

    /// Start recording: the bar, the handle and the label hide, and as soon as the screen capture has
    /// started, every source records into a new project (docs/ui.md, R5). There's no countdown.
    /// How far this camera runs behind this mic, in seconds, as set in Settings (docs/decisions.md, 83).
    private var measuredCameraDelay: TimeInterval {
        guard isCameraOn, isMicOn, let cameraID, let micID else { return 0 }
        return SyncCalibrations.load().calibration(camera: cameraID, mic: micID)?.offset ?? 0
    }

    func startRecording() {
        guard startConditions.canStart, let format else { return }
        // Nil with no screen: the camera is recorded alone.
        let placement = recordsScreen ? area.placement : nil
        problem = nil
        well = .preview
        area.takeStarting()
        app?.dock.tuckAway()
        let id = UUID()
        state = .starting(id: id, task: Task { await startTake(id: id, format: format, placement: placement) })
        handOver()
    }

    /// As the take starts, the element hands over to the Recording Panel in the view and at the width last used on
    /// this display, in the place it had there, the preview at Full's width the first time (docs/ui.md, R10;
    /// docs/decisions.md, 82). Start over, with the panel already up, keeps it as it is.
    private func handOver() {
        guard !panel.isShowing else { return }
        element.handOver { [weak self] screen in
            guard let self, self.phase.allowsPanelHandOver, let window = self.panel.showForRecording(on: screen),
                  let picture = self.panel.pictureFrame else { return nil }
            window.makeKey()
            return (window, picture, self.panel.shows == .camera)
        }
    }

    private func startTake(id: UUID, format: VideoFormat, placement: AreaPlacement?) async {
        guard !Task.isCancelled, isCurrentStart(id) else { return }
        // Screen Recording access is needed only for a screen.
        if placement != nil, !ScreenCapture.hasPermission { ScreenCapture.requestPermission() }
        let systemAudio = capturesSystemAudio
        let reportStop: @Sendable (String) -> Void = { [weak self] reason in
            Task { @MainActor in self?.screenStopped(reason, attemptID: id) }
        }
        let screenTask = placement.map { placement in Task {
            let screen = try await ScreenCapture.make(
                displayID: placement.displayID,
                area: AreaGeometry.sourceRect(for: placement.frame, onDisplay: placement.displayFrame),
                capturesSystemAudio: systemAudio
            )
            // Before it starts, so a stop while starting is caught too.
            screen.onStop = reportStop
            try await screen.start()
            return screen
        } }
        let screen: ScreenCapture?
        do {
            screen = try await screenTask?.value
        } catch {
            if !Task.isCancelled, isCurrentStart(id) { returnToSetup(problem: error.localizedDescription) }
            return
        }
        guard !Task.isCancelled, isCurrentStart(id) else {
            await screen?.stop()
            return
        }
        if case .starting(_, _, let reason?) = state {
            await screen?.stop()
            guard isCurrentStart(id) else { return }
            return returnToSetup(problem: "The screen recording stopped before it began: \(reason)")
        }
        do {
            guard let app else { return }
            let title = RecordingSession.title(recordsScreen: screen != nil, at: .now)
            let folder = try ProjectFolder.create(at: app.library.newProjectURL(title: title), title: title)
            let session = try RecordingSession(
                project: folder,
                sources: .init(
                    screen: screen,
                    camera: isCameraOn ? camera : nil,
                    mic: isMicOn ? mic : nil,
                    captureArea: placement?.area
                ),
                lipSync: measuredCameraDelay
            )
            // A track that stops recording stops the take there.
            session.onTrackFailure { [weak self] failure in
                Task { @MainActor in self?.trackFailed(failure, attemptID: id) }
            }
            session.start()
            // The screen log starts with the take's clock; a log that can't start doesn't stop the take.
            var screenLog: ScreenActivityLogger?
            if screen != nil, let placement {
                let logger = ScreenActivityLogger(project: folder.url, name: session.takeFolder.lastPathComponent, area: placement.frame,
                                                  scale: Double(NSScreen.with(id: placement.displayID)?.backingScaleFactor ?? 2), clock: session.clock)
                do {
                    try logger.start()
                    screenLog = logger
                } catch {
                    NSLog("CueCan: the screen log couldn't start: %@", error.localizedDescription)
                }
            }
            elapsed = 0
            state = .recording(Take(attemptID: id, screen: screen, session: session, project: folder, format: format, framings: framings,
                                    look: look, screenLog: screenLog, recordsCamera: isCameraOn))
            element.recordingStarted()
            area.recordingStarted()
            // Access may have been granted during startup; a visible preview must retry.
            preview.areaChanged()
            startTicker()
        } catch {
            await screen?.stop()
            guard isCurrentStart(id) else { return }
            returnToSetup(problem: error.localizedDescription)
        }
    }

    /// The screen stream stopped by itself, such as when its display was disconnected.
    private func screenStopped(_ reason: String, attemptID: UUID) {
        switch state {
        case .starting(let id, let task, _) where id == attemptID:
            state = .starting(id: id, task: task, stopped: reason)
        case .recording(let take), .paused(let take):
            guard take.attemptID == attemptID else { return }
            take.session.trackFailed(.screen, reason: reason)
        default: break
        }
    }

    /// A track stopped recording: the take stops and is saved up to here, and the alert says which track
    /// and when.
    private func trackFailed(_ failure: TrackFailure, attemptID: UUID) {
        switch state {
        case .recording(let take), .paused(let take):
            guard take.attemptID == attemptID else { return }
            Task { await stop() }
        default: break
        }
    }

    /// A cancelled attempt may still finish stopping its stream after another start has begun.
    private func isCurrentStart(_ id: UUID) -> Bool {
        guard case .starting(let current, _, _) = state else { return false }
        return current == id
    }

    /// Esc while the take is starting: everything closes, as while setting up, and nothing is saved
    /// (docs/decisions.md, 79).
    func cancelStart() {
        guard case .starting = state else { return }
        endSetup()
    }

    /// The start failed before the take began: back to setting up, with the element as it was.
    private func returnToSetup(problem: String?) {
        state = .settingUp
        self.problem = problem
        area.startCancelled()
        panel.hide()
        element.comeBack()
        element.focus()
        app?.dock.bringBack()
    }

    /// Settings, from the element's title bar, on Recording (docs/decisions.md, 78).
    func openRecordingSettings() {
        UserDefaults.standard.set(SettingsTab.recording.rawValue, forKey: SettingsTab.storageKey)
        app?.showSettings()
    }

    /// Shows the Layout choices in the well, or the preview again (docs/ui.md, R10). Opening them closes
    /// framing.
    func toggleLayoutChoices() {
        guard phase == .settingUp, recordsScreen, format != nil else { return }
        well = well == .choices ? .preview : .choices
    }

    /// Framing in the well, on one kind of camera slot (docs/ui.md, R8 and R10), from a camera's icon on the
    /// preview; on that slot again, back to the preview. Opening it closes the Layout choices.
    func toggleFraming(_ slot: CameraSlot) {
        guard phase == .settingUp, framingBlocker == nil else { return }
        well = framingSlot == slot ? .preview : .framing(slot)
    }

    /// The strip's framing circle: framing on the main camera's slot (the camera beside or over the screen
    /// in the video; in Vertical, the Short's), or back to the preview.
    func toggleMainFraming() {
        if framingSlot != nil {
            well = .preview
        } else if let slot = formatCameraSlots.first {
            toggleFraming(slot)
        }
    }

    func togglePause() {
        switch state {
        case .recording(let take):
            take.session.pause()
            state = .paused(take)
        case .paused(let take):
            take.session.resume()
            state = .recording(take)
        default:
            break
        }
    }

    /// Stops, closes every file, adds the recording to its project and starts processing it. Stop always saves.
    func stop() async {
        guard let take = state.take else { return }
        state = .saving
        ticker?.cancel()
        let failure = take.session.trackFailure
        var saved = false
        do {
            var recorded = try await take.session.stop()
            await take.screen?.stop()
            if let log = take.screenLog {
                // The take is saved without its screen log rather than not at all.
                do {
                    recorded.screenLog = try log.finish(clockOffset: recorded.clockOffset)
                } catch {
                    NSLog("CueCan: the screen log couldn't be saved: %@", error.localizedDescription)
                }
            }
            let source = try recorded.add(to: take.project, format: take.format)
            if take.recordsCamera, source.track(.camera) == nil {
                problem = "Saved without the camera, which sent no picture."
            }
            // The take opens showing what was recorded: all of it as one clip (docs/decisions.md, 62), framed
            // as it was set while recording.
            _ = try take.project.updateEdit(author: .system("CueCan"), reason: "Started from the whole recording") { edit in
                // New takes start with the chosen preset (the source's, which the clip's automatic layout
                // follows) and the last look: the clip gets the side toggles, the edit the inset and what every
                // clip shares (docs/decisions.md, 66 and 68).
                if edit.main.isEmpty { edit.addWholeSource(source, look: take.look.clip) }
                edit.look = take.look.shared
                if !take.framings.isEmpty, source.track(.camera) != nil { edit.setFramings(take.framings, for: source.id) }
            }
            if recorded.micLostAt != nil {
                problem = "The mic disappeared. Everything up to then was saved."
            }
            if let failure { problem = failure.message(saved: recorded.lostTracks.isEmpty) }
            if !recorded.lostTracks.isEmpty {
                let names = recorded.lostTracks.map { TrackFailure(kind: $0, at: 0, reason: "").trackName }
                let note = "The \(names.formatted(.list(type: .and))) couldn’t be read, so the take was saved without \(names.count == 1 ? "it" : "them")."
                problem = [problem, note].compactMap { $0 }.joined(separator: " ")
            }
            saved = true
        } catch {
            take.screenLog?.stop()
            await take.screen?.stop()
            problem = [failure?.message(saved: false), error.localizedDescription].compactMap { $0 }.joined(separator: " ")
        }
        endSetup()
        if saved { app?.projectAdded(take.project) }
        if let problem { Self.tell(problem) }
    }

    /// Discard: throws the take away and stops. It's deleted outright, with no Trash (docs/decisions.md, 51).
    func discard() async {
        guard await discardTake() else { return }
        endSetup()
    }

    /// Start over: throws the take away and records again right away, with the same settings.
    func startOver() async {
        guard await discardTake() else { return }
        state = .settingUp
        startRecording()
    }

    /// Stops the writers and deletes the project folder the recording created when it started.
    private func discardTake() async -> Bool {
        guard let take = state.take, let app else { return false }
        state = .discarding
        ticker?.cancel()
        take.session.discard()
        take.screenLog?.discard()
        await take.screen?.stop()
        elapsed = 0
        do {
            try DiscardedTake.delete(take.project, in: app.library.projectsFolder)
        } catch {
            Self.tell(error.localizedDescription)
        }
        return true
    }

    /// Ends the whole setup: the bar, the area and the panel go (snapped windows stay where they are), and the
    /// projects window and the Dock icon come back if they were tucked away.
    private func endSetup() {
        well = .preview
        if case .starting(_, let task, _) = state { task.cancel() }
        if case .preparing(_, let task) = preparation { task.cancel() }
        preparation = .idle
        ticker?.cancel()
        state = .idle
        destination = nil
        elapsed = 0
        removeKeyMonitor()
        element.hide()
        area.hide()
        panel.hide()
        preview.areaChanged()
        sleep()
        app?.dock.bringBack()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let take = self.state.take else { return }
                self.elapsed = take.session.clock.elapsed
                // A camera that stops sending pictures fails like any other track.
                if take.recordsCamera, take.session.cameraHasStalled(threshold: 3) {
                    take.session.trackFailed(.camera, reason: "the camera stopped sending pictures")
                }
            }
        }
    }

    /// A problem after the panels have gone, said in an alert so it isn't lost.
    private static func tell(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}

/// What the setup element's well shows (docs/ui.md, R10).
enum SetupWell: Equatable {
    /// The live preview of the export.
    case preview
    /// The Layout choices.
    case choices
    /// The whole camera frame, framing one kind of slot.
    case framing(CameraSlot)
}

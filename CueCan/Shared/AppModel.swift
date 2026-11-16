import AppKit
import Foundation
import Observation
import ProjectKit
import SwiftUI
import UpdateKit

/// What the whole app shares: where projects are, the recorder, background processing and the Dock icon.
@Observable
final class AppModel {
    let library = ProjectLibrary()
    let processing = ProcessingCenter()
    let exports = ExportCenter()
    var showsBackgroundTasks = false
    /// View-instance identities prevent a disappearing editor from clearing a replacement's activity.
    var preparingPreviews: [UUID: String] = [:]
    /// Corrections being timed in visible editors; closing an editor cancels its correction.
    var timingTranscripts: [UUID: String] = [:]
    var normalizingPreviews: [UUID: String] = [:]
    @ObservationIgnored let dock = DockIconController()
    /// Updates (docs/decisions.md, 91 and 97).
    @ObservationIgnored let updater = AppUpdater()
    /// The line of news from cuecan.com (docs/decisions.md, 97).
    let news = NewsModel()
    /// When this build stops starting recordings (docs/decisions.md, 98); nil for a build from Xcode.
    /// Read each time it's asked, so a day set while the app runs counts at once.
    var betaExpiry: BetaExpiry? { Self.builtOn.flatMap { BetaExpiry(builtOn: $0) } }

    /// The day the build was made, from its Info.plist. A Debug build can be given one to try the ending,
    /// with the `betaBuiltOn` default: set it from Xcode's debugger or Terminal.app, since a sandboxed
    /// agent shell can write somewhere the app doesn't read (the `cuecan-run-app` skill).
    private static var builtOn: String? {
        #if DEBUG
        if let tried = UserDefaults.standard.string(forKey: "betaBuiltOn") { return tried }
        #endif
        return Bundle.main.object(forInfoDictionaryKey: "CueCanBuiltOn") as? String
    }

    /// Says the beta has ended, if it has, and offers the update. True when it stood in the way.
    func stopsForEndedBeta() -> Bool {
        guard let betaExpiry, betaExpiry.hasEnded(at: .now) else { return false }
        let alert = NSAlert()
        alert.messageText = "This beta version has expired"
        alert.informativeText = "Update to keep recording."
        alert.addButton(withTitle: "Check for Updates…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { updater.checkForUpdates() }
        return true
    }
    @ObservationIgnored private(set) lazy var recorder = RecorderModel(app: self)
    /// The first-run setup window (docs/ui.md, board 11).
    let accessSetup = AccessSetupModel()
    let speechModels = SpeechModelsModel()
    /// The projects window shows this project when set.
    var openProject: URL?
    /// Bumped when a project is added, so lists reload.
    private(set) var libraryRevision = 0
    /// SwiftUI's actions for opening windows, kept from the first view that has them, so the menu bar item
    /// and the recorder can open the projects window and Settings.
    @ObservationIgnored var openWindow: OpenWindowAction?
    @ObservationIgnored var openSettings: OpenSettingsAction?

    /// Brings the projects window forward, with its Dock icon (docs/decisions.md, 29).
    func showProjects() {
        dock.projectsWindowWillOpen()
        NSApp.activate()
        if let window = dock.projectsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "projects")
        }
    }

    /// Opens the project most recently opened or recorded.
    func openLastProject() {
        guard let last = library.projects().first else {
            showProjects()
            return
        }
        openProject = last.url
        showProjects()
    }

    /// Opens the setup window again, from Settings.
    func showAccessSetup() {
        accessSetup.step = .access
        NSApp.activate()
        if let window = accessSetup.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "setup")
        }
    }

    /// Closes the setup window for good: it isn't shown at launch again. Then the first recording's setup,
    /// or Projects, so closing it never leaves CueCan with nothing on screen.
    func finishAccessSetup(thenRecord: Bool) {
        accessSetup.finish()
        accessSetup.window?.close()
        if thenRecord { recorder.openSetup() } else { showProjects() }
    }

    func showSettings() {
        NSApp.activate()
        openSettings?()
    }

    func showBackgroundTasks() {
        showsBackgroundTasks = true
        showProjects()
    }

    /// Why a take couldn't be duplicated, for the projects window to say.
    var duplicateProblem: String?

    /// Duplicates a take beside itself and opens the copy: its own edit over the same recordings, for a
    /// Short that should be cut or look different from its video (docs/decisions.md, 77). The copy's folder
    /// shares the recordings' data on disk, so it costs almost no space.
    func duplicate(_ url: URL) {
        // Processing is still writing the take's transcript and cleaned voice: copy it once it's whole.
        guard processing.activity[url] == nil else {
            showBackgroundTasks()
            return
        }
        do {
            let copy = try library.duplicate(try ProjectFolder(opening: url))
            library.noteOpened(copy)
            libraryRevision += 1
            openProject = copy.url
        } catch {
            duplicateProblem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func projectAdded(_ folder: ProjectFolder) {
        library.noteOpened(folder)
        libraryRevision += 1
        openProject = folder.url
        processing.process(folder)
        showProjects()
    }
}

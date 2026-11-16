import AppKit
import RecorderKit
import ProjectKit
import SwiftUI
import UpdateKit

/// The projects window (docs/ui.md, P1 and P2; docs/decisions.md, 63): the takes as thumbnails in the
/// sidebar, and the open one in the editor beside them (E1).
struct ProjectsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var projects: [ProjectSummary] = []
    @State private var thumbnails = TakeThumbnails()
    @State private var confirming: URL?
    @State private var trashProblem: String?

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            ProjectSidebar(
                takes: projects,
                selection: $app.openProject,
                confirming: $confirming,
                thumbnails: thumbnails,
                moveToTrash: moveToTrash,
                duplicate: { app.duplicate($0) }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let item = app.news.visible {
                    NewsBanner(item: item) { app.news.dismiss() }
                }
            }
            .navigationSplitViewColumnWidth(260)
        } detail: {
            if let url = app.openProject {
                ProjectDetailView(url: url)
                    .id(url)
            } else {
                // Nothing to explain: the sidebar is beside it.
                Button("New recording") { app.recorder.openSetup() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem { BackgroundTasksButton() }
            ToolbarItem {
                if app.recorder.isRecording {
                    Button("Stop recording", systemImage: "stop.circle.fill") {
                        Task { await app.recorder.stop() }
                    }
                    .tint(.red)
                } else {
                    Button("New recording", systemImage: "record.circle") { app.recorder.openSetup() }
                        .disabled(app.recorder.phase != .idle && app.recorder.phase != .settingUp)
                }
            }
        }
        .background {
            // ⌘⌫ asks to move the selected take to the Trash.
            Button("Move to Trash") { confirming = app.openProject }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(app.openProject == nil)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .alert("Couldn’t move the recording to the Trash", isPresented: Binding(get: { trashProblem != nil }, set: { if !$0 { trashProblem = nil } })) {
            Button("OK") { trashProblem = nil }
        } message: {
            Text(trashProblem ?? "")
        }
        .alert("Couldn’t duplicate the recording", isPresented: Binding(get: { app.duplicateProblem != nil }, set: { if !$0 { app.duplicateProblem = nil } })) {
            Button("OK") { app.duplicateProblem = nil }
        } message: {
            Text(app.duplicateProblem ?? "")
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(ProjectsWindowReporter(dock: app.dock))
        .task(id: app.libraryRevision) {
            app.openWindow = openWindow
            app.openSettings = openSettings
            await reload()
        }
        .task {
            // News follows the same switch as updates: turning it off in Settings stops both.
            if app.updater.checksAutomatically { await app.news.refreshIfDue() }
        }
        .task {
            // Claude can add projects with the app open; look again now and then.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await reload()
            }
        }
    }

    private func reload() async {
        let library = app.library
        projects = await Task.detached { library.projects() }.value
    }

    /// Moves a take's folder to the Trash, where it can be put back. If it's open, the editor moves to the
    /// take below it first, or the one above.
    private func moveToTrash(_ url: URL) {
        guard app.processing.activity[url] == nil, app.exports.activity(for: url) == nil else {
            app.showBackgroundTasks()
            return
        }
        let ordered = projects.sorted(by: ProjectSidebar.comesFirst)
        if app.openProject == url, let index = ordered.firstIndex(where: { $0.url == url }) {
            let next = index + 1 < ordered.count ? ordered[index + 1] : index > 0 ? ordered[index - 1] : nil
            app.openProject = next?.url
        }
        Task {
            // Let the editor close the take before its folder moves.
            try? await Task.sleep(for: .milliseconds(200))
            guard app.processing.activity[url] == nil, app.exports.activity(for: url) == nil else {
                app.showBackgroundTasks()
                return
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                projects.removeAll { $0.url == url }
                thumbnails.forget(url)
            } catch {
                trashProblem = error.localizedDescription
            }
            await reload()
        }
    }
}

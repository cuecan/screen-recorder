import AppKit
import ProjectKit
import RenderKit
import SwiftUI

/// The editor (docs/ui.md, E1 to E3; docs/decisions.md, 54 to 61): the previews in the project's format on
/// top with the inspector beside them, the tools and transport under them, and the four-lane timeline at the
/// bottom. Claude's changes show up live, because the editor watches `edit.json`.
struct EditorView: View {
    @Environment(AppModel.self) private var app
    @State private var model: EditorModel
    @State private var exporting = false
    @State private var showsHistory = false
    @State private var showsInspector = true
    @SceneStorage("editorInspectorWidth") private var inspectorWidth = 320.0
    @State private var editorActivityID = UUID()
    @State private var isVisible = false

    init(folder: ProjectFolder) {
        _model = State(initialValue: EditorModel(folder: folder))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ZStack {
                        PreviewPanels(model: model)
                            .padding(20)
                        overlayStates
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.3))
                    .overlay(alignment: .topLeading) {
                        status
                            .padding(12)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                if showsInspector {
                    InspectorResizeDivider(width: $inspectorWidth)
                    InspectorView(model: model)
                        .frame(width: inspectorWidth)
                        .background(.background)
                }
            }
            Divider()
            TransportBar(model: model)
            Divider()
            TimelineView(model: model)
        }
        .navigationTitle(model.project?.title ?? model.folder.url.lastPathComponent)
        .navigationSubtitle(subtitle)
        .focusedSceneValue(\.editorModel, model)
        .toolbar { toolbar }
        .sheet(isPresented: $exporting) { EditorExportSheet(model: model) }
        .onChange(of: model.editingWords) { _, words in
            // Fix Text… opens in the transcript, so the inspector has to be showing it.
            if words != nil {
                showsInspector = true
                model.selection = .none
                model.inspectorTab = .transcript
            }
        }
        .background(EditorKeyboardMonitor(model: model))
        .task { await model.watch() }
        .onAppear { isVisible = true; updateBackgroundActivity() }
        .onChange(of: model.isPreparing) {
            if isVisible { updateBackgroundActivity() }
        }
        .onChange(of: model.pendingFix?.id) {
            if isVisible { updateBackgroundActivity() }
        }
        .onChange(of: model.previewLoudness.isPreparing) {
            if isVisible { updateBackgroundActivity() }
        }
        .onDisappear {
            isVisible = false
            app.preparingPreviews.removeValue(forKey: editorActivityID)
            app.timingTranscripts.removeValue(forKey: editorActivityID)
            app.normalizingPreviews.removeValue(forKey: editorActivityID)
        }
    }

    /// Progress and feedback must not resize the preview or inspector while an edit is being prepared.
    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorProcessingStatus(folder: model.folder, processing: app.processing)
            if let problem = model.problem {
                HStack {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        .lineLimit(2).help(problem)
                    Button("Dismiss") { model.clear() }.controlSize(.small)
                }
                .font(.callout)
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
            if let notice = model.notice, model.problem == nil {
                HStack {
                    Label(notice, systemImage: "info.circle").foregroundStyle(.secondary)
                        .lineLimit(2).help(notice)
                    Button("Dismiss") { model.notice = nil }.controlSize(.small)
                }
                .font(.callout)
                .padding(10)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func updateBackgroundActivity() {
        let title = model.project?.title ?? model.folder.url.lastPathComponent
        if model.isPreparing { app.preparingPreviews[editorActivityID] = title }
        else { app.preparingPreviews.removeValue(forKey: editorActivityID) }
        if model.pendingFix != nil { app.timingTranscripts[editorActivityID] = title }
        else { app.timingTranscripts.removeValue(forKey: editorActivityID) }
        if model.previewLoudness.isPreparing { app.normalizingPreviews[editorActivityID] = title }
        else { app.normalizingPreviews.removeValue(forKey: editorActivityID) }
    }

    /// The shape the take's screen was recorded at, as the recorder writes it ("Screen 16:9"), when every
    /// take in the project shares one; nil for the camera alone.
    private var screenRatio: CaptureArea.Ratio? {
        let ratios = Set(model.project?.sources.compactMap { $0.captureArea?.ratio } ?? [])
        return ratios.count == 1 ? ratios.first : nil
    }

    /// Under the take's name: its format, then the screen's shape with the recorder's own symbol.
    private var subtitle: Text {
        guard let screenRatio else { return Text(formatName) }
        return Text("\(formatName)   \(Image(systemName: "display")) Screen \(screenRatio.rawValue)")
    }

    private var formatName: String {
        guard let project = model.project else { return "" }
        let screenless = project.sources.allSatisfy { $0.track(.screen) == nil }
        return screenless ? project.effectiveFormat.cameraOnlyLabel : project.effectiveFormat.label
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
                .help(model.history.last.map { "Undo \($0.reason)" } ?? "Nothing to undo")
                .disabled(model.history.isEmpty)
            Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }
                .disabled(!model.canRedo)
            Button("History", systemImage: "clock.arrow.circlepath") { showsHistory.toggle() }
                .popover(isPresented: $showsHistory, arrowEdge: .bottom) { HistoryPopover(model: model) }
        }
        ToolbarItem {
            Button("Project settings", systemImage: "slider.horizontal.3") {
                model.inspectProject()
                showsInspector = true
            }
                .help("Project appearance and background")
                .disabled(model.edit == nil)
        }
        ToolbarItem {
            ClaudeStatus()
        }
        ToolbarItem {
            Button(showsInspector ? "Hide inspector" : "Show inspector", systemImage: "sidebar.right") { showsInspector.toggle() }
                .help(showsInspector ? "Hide inspector" : "Show inspector")
        }
        ToolbarItem {
            Button("Export…", systemImage: "square.and.arrow.up") { model.pause(); exporting = true }
                .disabled(model.timeline == nil)
        }
    }

    @ViewBuilder
    private var overlayStates: some View {
        if model.isPreparing, model.timeline == nil {
            ProgressView("Preparing preview…")
                .padding(20)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
        } else if let problem = model.previewProblem {
            ContentUnavailableView {
                Label("Preview unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(problem).textSelection(.enabled)
            } actions: {
                Button("Show project in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.folder.url]) }
                Button("Retry", action: model.retryPreview)
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        } else if model.timeline == nil, model.edit?.main.isEmpty == true {
            // Only when everything was cut on purpose: a take opens with all of it on the timeline (62).
            VStack(spacing: 10) {
                Text("The timeline is empty").font(.headline)
                Text("Everything was cut. Undo, or put a recording back.").foregroundStyle(.secondary)
                ForEach(model.project?.sources ?? [], id: \.id) { source in
                    Button("Put back all of \(source.name)") { model.addWholeSource(source.id) }
                }
            }
            .padding(24)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
    }
}

/// "Claude connected" in the toolbar: whether Claude has touched this Mac's projects, and how to connect it.
private struct ClaudeStatus: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Label("Claude", systemImage: "sparkles")
        }
        .help("Connect Claude in Settings to edit by asking.")
    }
}

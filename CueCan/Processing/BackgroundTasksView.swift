import AppKit
import ProjectKit
import RenderKit
import SwiftUI

/// One discoverable place for exports, take processing and preview preparation. Unknown-length stages
/// use a spinner; file percentages come from the renderer, without inventing a combined ETA.
struct BackgroundTasksButton: View {
    @Environment(AppModel.self) private var app

    private var count: Int { app.exports.activeCount + app.processing.activity.count + app.preparingPreviews.count + app.timingTranscripts.count + app.normalizingPreviews.count }
    private var hasProblem: Bool {
        !app.processing.problems.isEmpty || app.exports.entries.contains {
            if !$0.job.warnings.isEmpty { return true }
            if case .finished(.failed) = $0.job.phase { return true }
            return false
        }
    }

    var body: some View {
        @Bindable var app = app
        Button {
            app.showsBackgroundTasks.toggle()
        } label: {
            HStack(spacing: 5) {
                if count > 0 {
                    ProgressView().controlSize(.small).frame(width: 18, height: 18)
                } else {
                    Image(systemName: hasProblem ? "exclamationmark.circle" : "checklist")
                }
                if count > 0 { Text(count, format: .number).monospacedDigit() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { app.showsBackgroundTasks.toggle() }
        .accessibilityLabel("Background tasks")
        .accessibilityValue(count == 0 ? (hasProblem ? "Needs attention" : "No tasks running") : "\(count) running or queued")
        .help("Background tasks")
        .popover(isPresented: $app.showsBackgroundTasks, arrowEdge: .bottom) { BackgroundTasksView() }
    }
}

struct BackgroundTasksView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Background tasks").font(.headline)
                Spacer()
                if app.exports.entries.contains(where: { !$0.isActive }) {
                    Button("Clear finished") { app.exports.clearFinished() }.controlSize(.small)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !app.preparingPreviews.isEmpty {
                        section("Previews")
                        ForEach(app.preparingPreviews.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.preparingPreviews[id] ?? "Take")
                                    Text("Preparing preview…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !app.normalizingPreviews.isEmpty {
                        section("Loudness preview")
                        ForEach(app.normalizingPreviews.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.normalizingPreviews[id] ?? "Take")
                                    Text("Preparing normalized sound…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !app.timingTranscripts.isEmpty {
                        section("Transcript corrections")
                        ForEach(app.timingTranscripts.keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.timingTranscripts[id] ?? "Take")
                                    Text("Timing corrected words…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !app.processing.activity.isEmpty || !app.processing.problems.isEmpty {
                        section("Processing")
                        ForEach(app.processing.activity.keys.sorted(by: { $0.path < $1.path }), id: \.self) { url in
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Button(url.lastPathComponent) { open(url) }.buttonStyle(.link)
                                    Text(app.processing.activity[url] ?? "Processing…").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(app.processing.problems.keys.sorted(by: { $0.path < $1.path }), id: \.self) { url in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(url.lastPathComponent).fontWeight(.medium)
                                Label(app.processing.problems[url] ?? "Processing failed", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                                Button("Open take") { open(url) }
                            }
                        }
                    }
                    if !app.exports.entries.isEmpty {
                        section("Exports")
                        Text("Exports use the edit as it was when you pressed Export.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(app.exports.entries.reversed()) { entry in
                            ExportActivityRow(entry: entry, center: app.exports)
                        }
                    }
                    if app.preparingPreviews.isEmpty, app.timingTranscripts.isEmpty, app.normalizingPreviews.isEmpty, app.processing.activity.isEmpty, app.processing.problems.isEmpty, app.exports.entries.isEmpty {
                        ContentUnavailableView("No tasks running", systemImage: "checkmark.circle")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func section(_ name: String) -> some View { Text(name).font(.caption.weight(.medium)).foregroundStyle(.secondary) }

    private func open(_ url: URL) {
        app.openProject = url
        app.showsBackgroundTasks = false
    }
}

private struct ExportActivityRow: View {
    let entry: ExportQueue.Entry
    let center: ExportCenter

    private var files: [URL] { entry.job.rows.flatMap(\.files) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).fontWeight(.medium).lineLimit(2)
                Spacer(minLength: 8)
                if entry.isActive {
                    Button(entry.job.phase == .setup ? "Cancel" : "Stop") { center.stop(entry.id) }
                        .controlSize(.small).disabled(entry.job.phase == .stopping)
                }
            }
            Text(entry.status).font(.caption).foregroundStyle(.secondary)
            ForEach(entry.job.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.label)
                        Spacer()
                        if row.id != .handoff || !entry.isActive {
                            Text(!entry.isActive && row.files.isEmpty ? "Not completed" : row.status).monospacedDigit()
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if entry.isActive {
                        if row.state == .preparing || (row.id == .handoff && entry.job.phase != .setup) { ProgressView() }
                        else { ProgressView(value: row.progress) }
                    }
                }
            }
            if case .finished(.failed(let message)) = entry.job.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(entry.job.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let plan = center.plan(for: entry.id) {
                Text(plan.destination.path(percentEncoded: false))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(plan.destination.path(percentEncoded: false))
                if !entry.isActive {
                    HStack {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(files.isEmpty ? [plan.destination] : files)
                        }
                        if let video = files.first(where: { $0.pathExtension == "mp4" }) {
                            Button("Open video") { NSWorkspace.shared.open(video) }
                        }
                    }
                    .controlSize(.small)
                }
            }
            Divider()
        }
    }
}

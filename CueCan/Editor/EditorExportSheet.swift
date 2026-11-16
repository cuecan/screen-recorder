import AppKit
import ProjectKit
import RenderKit
import SwiftUI

/// Reviews the files, name and destination before handing a frozen export to the app-owned queue.
/// Dismissing this setup sheet never cancels an export that has already started.
struct EditorExportSheet: View {
    let model: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Kind: Hashable { case finished, handoff }
    @State private var kind = Kind.finished
    @State private var shapes: Set<OutputShape> = []
    @State private var transcript = true
    @State private var codec = ExportSettings.Codec.hevc
    @State private var fourK = false
    @State private var splitAtSilences = false
    @State private var destination = ExportPreferences.folder()
    @State private var name = ""
    @State private var inputs: RenderInputs?
    @State private var problem: String?
    @State private var starting = false
    @State private var preparation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Export").font(.title2.weight(.semibold))
                Text("\(model.project?.title ?? "Take") · \(model.clock(model.duration))")
                    .foregroundStyle(.secondary).lineLimit(2)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    setup
                    Divider()
                    destinationRows
                    if let plan {
                        fileReview(plan)
                    } else if problem == nil {
                        ProgressView("Preparing export…").controlSize(.small)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 530)
            .disabled(starting)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Uses the edit when you press Export. You can keep editing.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(starting ? "Preparing…" : "Export") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(starting || !canExport)
            }
        }
        .padding(22)
        .frame(width: 510)
        .task {
            shapes = Set(model.outputs)
            name = ExportPlan.baseName(model.project?.title ?? "Export")
            do {
                let folder = model.folder
                inputs = try await Task.detached { try RenderInputs.load(folder) }.value
            } catch { problem = error.localizedDescription }
        }
        .onDisappear { preparation?.cancel() }
    }

    @ViewBuilder
    private var setup: some View {
        Picker("Export", selection: $kind) {
            Text("Finished video").tag(Kind.finished)
            Text("For another editor").tag(Kind.handoff)
        }
        .pickerStyle(.segmented).labelsHidden()
        switch kind {
        case .finished:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.outputs, id: \.self) { shape in
                    Toggle(shape == .landscape ? "Video · 16:9" : "Short · 9:16", isOn: binding(shape))
                }
                Toggle("Transcript · SRT and text", isOn: $transcript)
            }
            LabeledContent("Size") {
                Picker("Size", selection: $fourK) {
                    Text("1080p").tag(false)
                    Text("4K").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            if fourK, let camera = smallestCamera, camera.height < 2160 {
                Text("The camera was recorded smaller than 4K, so it will look softer.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Video settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Codec", selection: $codec) {
                        ForEach(ExportSettings.Codec.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("Sound is levelled to −14 LUFS for YouTube.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        case .handoff:
            Text("A timeline for Final Cut or Resolve, with captions and a transcript.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Backgrounds, rounded corners and borders don’t carry over.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Split at silences", isOn: $splitAtSilences)
                .help("Cuts at every silence without removing anything")
        }
    }

    private var destinationRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Name") {
                TextField("Export name", text: $name).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Export name")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Save to").fixedSize()
                Text(destination.path(percentEncoded: false))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .help(destination.path(percentEncoded: false))
                Button("Choose…") { choose() }
            }
        }
    }

    private func fileReview(_ plan: ExportPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Files").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            ForEach(plan.outputURLs, id: \.self) { file in
                Label(file.lastPathComponent, systemImage: file.pathExtension == "mp4" ? "film" : "doc.text")
                    .font(.callout).lineLimit(2).textSelection(.enabled)
            }
            if !conflicts.isEmpty {
                Text("Already in use: \(conflicts.map(\.lastPathComponent).joined(separator: ", ")). Choose another name or folder.")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var operation: ExportPlan.Kind {
        kind == .finished
            ? .finished(outputs: OutputShape.allCases.filter { shapes.contains($0) }, transcript: transcript,
                        settings: ExportSettings(codec: codec, scale: fourK ? 2 : 1))
            : .handoff(splitAtSilences: splitAtSilences)
    }
    private var plan: ExportPlan? {
        inputs.map { ExportPlan(inputs: $0, destination: destination, kind: operation, name: name) }
    }
    private var conflicts: [URL] { plan.map { app.exports.conflicts(for: $0) } ?? [] }
    private var canExport: Bool {
        inputs != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && conflicts.isEmpty
            && (kind == .handoff || !shapes.isEmpty || transcript)
    }
    private var smallestCamera: (width: Int, height: Int)? {
        let used = Set(model.edit?.main.map(\.source) ?? [])
        return model.project?.sources.filter { used.contains($0.id) }.compactMap { $0.track(.camera)?.media.video }
            .min { $0.height < $1.height }.map { ($0.width, $0.height) }
    }
    private func binding(_ shape: OutputShape) -> Binding<Bool> {
        Binding { shapes.contains(shape) } set: { isOn in
            if isOn { shapes.insert(shape) } else { shapes.remove(shape) }
        }
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose export folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        if panel.runModal() == .OK, let folder = panel.url {
            destination = folder
            ExportPreferences.remember(folder)
        }
    }
    private func start() {
        guard canExport else { return }
        let folder = model.folder
        let destination = destination
        let operation = operation
        let name = name
        starting = true
        problem = nil
        preparation = Task {
            do {
                // Snapshot off the main actor at Export, so later agent edits cannot change queued work.
                let inputs = try await Task.detached(priority: .userInitiated) { try RenderInputs.load(folder) }.value
                try Task.checkCancellation()
                try app.exports.enqueue(ExportPlan(inputs: inputs, destination: destination, kind: operation, name: name))
                ExportPreferences.remember(destination)
                dismiss()
                app.showsBackgroundTasks = true
            } catch is CancellationError {
                starting = false
            } catch {
                problem = error.localizedDescription
                starting = false
            }
        }
    }
}

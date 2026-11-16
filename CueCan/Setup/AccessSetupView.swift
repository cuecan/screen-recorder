import RecorderKit
import SwiftUI

/// The first-run setup window (docs/ui.md, board 11; docs/ui/mockups/FirstRun.html): each kind of access in
/// a row that asks macOS and shows when it's allowed, then connecting Claude.
struct AccessSetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let model = app.accessSetup
        AccessSetupContent(list: model.list, asking: model.asking, step: model.step,
                           models: app.speechModels.state, downloadModels: { app.speechModels.download() },
                           press: { model.press($0) },
                           go: { step in withAnimation(.snappy(duration: 0.25)) { model.step = step } },
                           startRecording: { app.finishAccessSetup(thenRecord: true) })
            .background(SetupWindowReporter(app: app))
            .onAppear {
                app.openWindow = openWindow
                app.openSettings = openSettings
                // A window opened again, from Settings or the Window menu, starts at the list.
                model.step = .access
                model.startFollowing()
                app.speechModels.check()
                NSApp.activate()
            }
            .onDisappear { model.stopFollowing() }
    }
}

/// The window's content for a given state, apart from the model so every state can be previewed.
struct AccessSetupContent: View {
    let list: AccessChecklist
    var asking: Set<AccessKind> = []
    let step: AccessSetupModel.Step
    var models = SpeechModelsModel.State.missing
    var downloadModels: () -> Void = {}
    let press: (AccessKind) -> Void
    let go: (AccessSetupModel.Step) -> Void
    let startRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Set up CueCan").font(.system(size: 22, weight: .semibold))
            switch step {
            case .access: access
            case .connect: connect
            }
        }
        .padding(EdgeInsets(top: 6, leading: 28, bottom: 24, trailing: 28))
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Access

    @ViewBuilder private var access: some View {
        Text("macOS asks before an app can record.").modifier(Lede())
        SetupRows {
            ForEach(AccessKind.allCases, id: \.self) { kind in
                if kind != AccessKind.allCases.first { RowDivider() }
                AccessRow(kind: kind, state: list.state(of: kind), isAsking: asking.contains(kind)) { press(kind) }
            }
        }
        HStack {
            Spacer()
            // The way on is the main action once CueCan can record; until then the Allow buttons are.
            if list.canRecord {
                Button("Continue") { go(.connect) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { go(.connect) }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Speech models and Claude

    @ViewBuilder private var connect: some View {
        SetupRows { SpeechModelsRow(state: models, download: downloadModels) }.padding(.top, 16)
        SectionLabel("Connect Claude").padding(.top, 18)
        SetupRows {
            HStack(spacing: 10) {
                Text(ClaudeCommand.claudeCode)
                    .font(.system(size: 11.5, design: .monospaced))
                    // Shown whole, on as many lines as it takes: it's what gets run.
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CopyButton(text: ClaudeCommand.claudeCode)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        // Optional, and said so: the app records, cuts and exports without Claude (docs/decisions.md, 96).
        Text("Optional. Run this once in a terminal, so Claude can cut what you record.")
            .font(.callout).foregroundStyle(.secondary)
            .padding(.top, 6)
        HStack {
            Button("Back") { go(.access) }
            Spacer()
            Button("Start a recording", action: startRecording)
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(.top, 20)
    }
}

/// The speech models: a download, its progress, then done.
private struct SpeechModelsRow: View {
    let state: SpeechModelsModel.State
    let download: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: "waveform")
            VStack(alignment: .leading, spacing: 1) {
                Text("Speech models").fontWeight(.semibold)
                switch state {
                case .failed(let reason):
                    Text(reason).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                case .downloading(let fraction):
                    ProgressView(value: fraction).padding(.top, 3)
                default:
                    Text("Transcribe on this Mac. About 960 MB.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            switch state {
            case .checking:
                ProgressView().controlSize(.small)
            case .missing:
                Button("Download", action: download)
            case .failed:
                Button("Try Again", action: download)
            case .downloading(let fraction):
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(.secondary)
            case .downloaded:
                Label("Downloaded", systemImage: "checkmark").fontWeight(.medium).foregroundStyle(.green)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .animation(.snappy(duration: 0.25), value: state)
        .accessibilityElement(children: .combine)
    }
}

/// One kind of access: what it's for, and a button that asks for it until it's allowed.
private struct AccessRow: View {
    let kind: AccessKind
    let state: AccessChecklist.RowState
    let isAsking: Bool
    let press: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var symbol: String {
        switch kind {
        case .camera: "video"
        case .microphone: "mic"
        case .screenRecording: "display"
        case .accessibility: "macwindow"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(systemName: symbol)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(kind.title).fontWeight(.semibold)
                    if kind.isOptional { Text("Optional").font(.caption).foregroundStyle(.tertiary) }
                }
                Text(kind.reason).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .waiting {
                    // Yellow reads on the dark window; on a light one it needs to be darker to be read.
                    Text(kind.settingsInstruction).font(.callout)
                        .foregroundStyle(colorScheme == .dark ? Color.yellow : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .animation(.snappy(duration: 0.25), value: state)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var control: some View {
        switch state {
        case .allowed:
            Label("Allowed", systemImage: "checkmark")
                .fontWeight(.medium).foregroundStyle(.green)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .waiting:
            Button("Open Settings", action: press)
        case .ask:
            // The optional row doesn't compete with the three that recording needs.
            if kind.isOptional {
                Button("Allow", action: press).disabled(isAsking)
            } else {
                Button("Allow", action: press).buttonStyle(.borderedProminent).disabled(isAsking)
            }
        }
    }
}

// MARK: - Pieces

private struct Lede: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(.secondary).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6).padding(.bottom, 18)
    }
}

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 6)
    }
}

/// A group of rows on one rounded panel.
private struct SetupRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RowDivider: View {
    var body: some View { Divider().opacity(0.6) }
}

private struct RowIcon: View {
    let systemName: String
    var tint: Color = .primary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

/// Copy, which says it copied for a moment.
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
    }
}

/// Tells the app which window the setup is in, and makes its close button finish the setup: closing is the
/// creator's choice, while a quit, or macOS reopening CueCan for Screen Recording, leaves it to come back.
private struct SetupWindowReporter: NSViewRepresentable {
    let app: AppModel

    func makeNSView(context: Context) -> ReportingView { ReportingView(app: app) }
    func updateNSView(_ view: ReportingView, context: Context) {}

    final class ReportingView: NSView {
        private let app: AppModel

        init(app: AppModel) {
            self.app = app
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            app.accessSetup.window = window
            app.dock.setupWindowAppeared(window)
            // ⌘W presses this button too.
            let close = window.standardWindowButton(.closeButton)
            close?.target = self
            close?.action = #selector(closePressed)
        }

        @objc private func closePressed() {
            app.finishAccessSetup(thenRecord: false)
        }
    }
}

// MARK: - Previews

private func previewList(_ statuses: [AccessKind: AccessStatus], asked: Set<AccessKind> = []) -> AccessChecklist {
    AccessChecklist(statuses: statuses, asked: asked)
}

#Preview("F-A · First opened") {
    AccessSetupContent(list: previewList([:]), step: .access, press: { _ in }, go: { _ in }, startRecording: {})
}

#Preview("F-B · Part way") {
    AccessSetupContent(list: previewList([.camera: .allowed, .microphone: .allowed], asked: [.screenRecording]),
                       step: .access, press: { _ in }, go: { _ in }, startRecording: {})
}

#Preview("All allowed") {
    AccessSetupContent(list: previewList([.camera: .allowed, .microphone: .allowed, .screenRecording: .allowed, .accessibility: .allowed]),
                       step: .access, press: { _ in }, go: { _ in }, startRecording: {})
}

#Preview("F-C · Models and Claude") {
    AccessSetupContent(list: previewList([:]), step: .connect, press: { _ in }, go: { _ in }, startRecording: {})
}

#Preview("Downloading") {
    AccessSetupContent(list: previewList([:]), step: .connect, models: .downloading(0.42), press: { _ in }, go: { _ in }, startRecording: {})
}

#Preview("Downloaded") {
    AccessSetupContent(list: previewList([:]), step: .connect, models: .downloaded, press: { _ in }, go: { _ in }, startRecording: {})
}

#Preview("Download failed") {
    AccessSetupContent(list: previewList([:]), step: .connect, models: .failed("The Internet connection appears to be offline."),
                       press: { _ in }, go: { _ in }, startRecording: {})
}

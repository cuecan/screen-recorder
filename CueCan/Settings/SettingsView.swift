import ProjectKit
import RecorderKit
import SwiftUI
import UpdateKit

/// Settings' tabs, remembered, so the setup element's Settings button can open it on Recording
/// (docs/ui.md, R10).
enum SettingsTab: String {
    case claude, recording

    static let storageKey = "settingsTab"
}

/// Settings (docs/ui.md, board 12): connecting Claude, and where recordings go.
struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var tab = SettingsTab.claude.rawValue

    var body: some View {
        TabView(selection: $tab) {
            Tab("Claude", systemImage: "sparkles", value: SettingsTab.claude.rawValue) { ClaudeSettings() }
            Tab("Recording", systemImage: "record.circle", value: SettingsTab.recording.rawValue) { RecordingSettings() }
        }
        // A grouped form brings its own margins.
        .frame(width: 560)
    }
}

private struct ClaudeSettings: View {
    var body: some View {
        Form {
            Section("Claude Code") {
                Text("Run this once in a terminal:")
                CopyableText(text: ClaudeCommand.claudeCode)
            }
            Section("Claude Desktop") {
                Text("Add this to Claude Desktop's config (Settings → Developer → Edit Config):")
                CopyableText(text: ClaudeCommand.desktopConfig)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RecordingSettings: View {
    @AppStorage(ProcessingCenter.savesScreenTextKey) private var savesScreenText = true
    @Environment(AppModel.self) private var app
    @State private var checksAutomatically = false

    /// The projects folder as Finder would say it: `~/Movies/CueCan`.
    private var projectsFolder: String {
        (ProjectLibrary.defaultProjectsFolder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }

    // Every row is a title with one line under it and one control at the trailing edge, so the titles, the
    // second lines and the controls each line up down the form.
    var body: some View {
        Form {
            Section {
                // docs/decisions.md, 83.
                LipSyncSettingRow()
                Toggle(isOn: $savesScreenText) {
                    Text("Save screen text")
                    Text("Reads what’s on screen after each recording, so agents can follow along.")
                }
            } footer: {
                Text("The mic is recorded raw, as 48 kHz mono.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent {
                    Button("Show") {
                        let folder = ProjectLibrary.defaultProjectsFolder
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                } label: {
                    Text("Projects folder")
                    Text(projectsFolder).textSelection(.enabled)
                }
                LabeledContent {
                    Button("Review…") { app.showAccessSetup() }
                } label: {
                    Text("Access")
                    Text("Camera, microphone, screen recording and Accessibility.")
                }
                // docs/decisions.md, 97.
                Toggle(isOn: $checksAutomatically) {
                    Text("Check for updates and news")
                    Text("From cuecan.com, about once a day.")
                }
                .onChange(of: checksAutomatically) { _, isOn in
                    if app.updater.checksAutomatically != isOn { app.updater.checksAutomatically = isOn }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { checksAutomatically = app.updater.checksAutomatically }
    }
}

/// Monospaced text with a Copy button.
struct CopyableText: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            }
        }
    }
}

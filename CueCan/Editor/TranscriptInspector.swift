import AppKit
import ProjectKit
import SwiftUI

/// With nothing selected, or words, the inspector shows the transcript (docs/ui.md, "The transcript in the
/// inspector"): the cut's length against the recording's, Edit or Full, and Find, over the text.
struct TranscriptInspector: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(length)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("How long the video is, of everything recorded")
                Spacer(minLength: 0)
                Picker("Show", selection: $model.transcriptMode) {
                    Text("Edit").tag(TranscriptReading.Mode.edit)
                    Text("Full").tag(TranscriptReading.Mode.full)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Full also shows what’s cut")
                Button("Find", systemImage: "magnifyingglass", action: find)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Find in the transcript (⌘F)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            commands
            Divider()
            if model.reading?.blocks.isEmpty ?? true {
                emptyTranscript
                    .frame(maxHeight: .infinity)
            } else {
                TranscriptTextView(model: model)
            }
        }
    }

    @ViewBuilder private var emptyTranscript: some View {
        if model.transcripts.transcripts.values.contains(where: { $0.items.contains(where: { !$0.isSilence }) }) {
            ContentUnavailableView("No words in this edit", systemImage: "text.alignleft",
                                   description: Text("Switch to Full to see the recording."))
        } else if let project = model.project, !project.sources.contains(where: { $0.primaryAudioTrack != nil }) {
            ContentUnavailableView("No microphone audio", systemImage: "mic.slash")
        } else if model.transcripts.transcripts.isEmpty {
            ContentUnavailableView("Not transcribed yet", systemImage: "text.alignleft",
                                   description: Text("Words appear after processing."))
        } else {
            ContentUnavailableView("No speech found", systemImage: "text.alignleft")
        }
    }

    /// The commands that act on the words as a whole: Remove Silences, with how long a pause has to be.
    private var commands: some View {
        HStack(spacing: 6) {
            Button { model.removeSilences() } label: {
                ViewThatFits(in: .horizontal) {
                    Text(model.passScope == nil ? "Remove Silences" : "Remove Silences in Selection").fixedSize()
                    Text(model.passScope == nil ? "Remove Silences" : "Remove Selected Silences").fixedSize()
                }
            }
            .controlSize(.small)
            .accessibilityLabel(model.passScope == nil ? "Remove Silences" : "Remove Silences in Selection")
            .help("Shortens every pause longer than this to \(Edit.defaultSilenceAir.formatted()) s, \(model.passScope == nil ? "in the whole edit" : "in the selected clips"). Edges you placed by hand stay put.")
            Text("over").foregroundStyle(.secondary)
            InspectorNumberField(title: "Shortest pause to remove, in seconds", value: model.silenceThreshold,
                                 range: Edit.silenceThresholds, step: 0.1, fractionDigits: 1) { model.silenceThreshold = $0 }
                .frame(width: 34, height: 22)
            Text("s").foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .disabled(model.transcripts.transcripts.isEmpty)
    }

    /// "8:02 of 12:40": the edit, of every recording.
    private var length: String {
        let recorded = model.project?.sources.reduce(0) { $0 + $1.duration } ?? 0
        return "\(Self.clock(model.duration)) of \(Self.clock(recorded))"
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60) : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private func find() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        guard let window = NSApp.keyWindow, let text = Self.transcriptView(in: window.contentView) else { return }
        window.makeFirstResponder(text)
        text.performTextFinderAction(item)
    }

    private static func transcriptView(in view: NSView?) -> TranscriptNSTextView? {
        guard let view else { return nil }
        if let text = view as? TranscriptNSTextView { return text }
        for subview in view.subviews { if let found = transcriptView(in: subview) { return found } }
        return nil
    }
}

import ProjectKit
import SwiftUI

/// A whole-mix audition of export loudness, without a video export or a change to clip levels.
struct LoudnessPreviewControls: View {
    @Bindable var model: EditorModel
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle { SectionTitle("Playback") }
            HStack(spacing: 8) {
                Toggle("Normalize playback", isOn: $model.normalizePreview)
                    .help("Plays at the export’s loudness.")
                Spacer(minLength: 0)
                ZStack {
                    if model.previewLoudness.isPreparing {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("Preparing normalized playback")
                            .help("Preparing normalized playback")
                    }
                }
                .frame(width: 16, height: 16)
            }
            if case .ready(_, hasAudio: false) = model.previewLoudness.state {
                Text("No audio").font(.caption).foregroundStyle(.secondary)
            } else if let audio = model.edit?.audio {
                Text("\(audio.loudnessTarget.formatted(.number.precision(.fractionLength(0...1)))) LUFS target · \(audio.truePeakCeiling.formatted(.number.precision(.fractionLength(0...1)))) dBTP ceiling")
                    .font(.caption).foregroundStyle(.secondary)
            }
            switch model.previewLoudness.state {
            case .off, .preparing, .ready: EmptyView()
            case .failed(_, let message):
                HStack {
                    Text("Couldn't normalize playback.").font(.caption).foregroundStyle(.secondary).help(message)
                    Button("Retry") { model.retryNormalizedPreview() }.controlSize(.small)
                }
            }
        }
    }
}

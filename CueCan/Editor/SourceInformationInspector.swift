import AppKit
import ProjectKit
import SwiftUI

struct SourceInformationInspector: View {
    let model: EditorModel
    let source: Source
    let expanded: Bool

    var body: some View {
        InspectorSection(source.name, expanded: expanded, storageKey: "sourceInfo.\(source.id)") {
            ForEach(source.tracks, id: \.kind) { track in
                VStack(alignment: .leading, spacing: 5) {
                    Text(name(of: track.kind)).font(.callout.weight(.semibold))
                    if let video = track.media.video {
                        InspectorRow("Resolution") { Text("\(video.width) × \(video.height)") }
                        InspectorRow("Capture rate") { Text("\(video.captureRate.formatted(.number.precision(.fractionLength(0...2)))) fps") }
                        InspectorRow("Codec") { Text(video.codec).textSelection(.enabled) }
                    }
                    if track.kind == .camera, let lipSync = source.lipSync {
                        InspectorRow("Lip sync") { Text("\(Int((lipSync * 1000).rounded())) ms") }
                            .help("How far the camera was moved to meet your voice.")
                    }
                    if let audio = track.media.audio {
                        InspectorRow("Sample rate") { Text("\((audio.sampleRate / 1000).formatted()) kHz") }
                        InspectorRow("Channels") { Text(audio.channels == 1 ? "Mono" : "\(audio.channels)") }
                    }
                    Button("Reveal \(name(of: track.kind).lowercased())", systemImage: "doc") {
                        NSWorkspace.shared.activateFileViewerSelecting([track.file.url(relativeTo: model.folder.url)])
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func name(of kind: SourceTrack.Kind) -> String {
        switch kind {
        case .screen: "Screen"
        case .camera: "Camera"
        case .video: "Video"
        case .microphone: "Microphone"
        case .systemAudio: "System audio"
        case .audio: "Audio"
        }
    }
}

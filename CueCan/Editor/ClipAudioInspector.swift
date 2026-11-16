import ProjectKit
import SwiftUI

/// Per-clip levels precede source processing, with explicit scope and genuine mixed selection values.
struct ClipAudioInspector: View {
    let model: EditorModel

    private var clips: [Clip] { model.selectedClips }
    private var ids: Set<ClipID> { Set(clips.map(\.id)) }
    private var mics: [Source] {
        let sources = Set(clips.map { $0.audio?.source ?? $0.source })
        return model.project?.sources.filter { sources.contains($0.id) && $0.primaryAudioTrack != nil } ?? []
    }
    private var hasSystem: Bool {
        clips.contains { $0.audio == nil && model.project?.source($0.source)?.track(.systemAudio) != nil }
    }

    var body: some View {
        InspectorSection("Levels", canReset: clips.contains { $0.isMuted || $0.voiceLevel != 0 || $0.systemAudioLevel != 0 }, reset: {
            model.setSound(.init(voiceLevel: 0, systemAudioLevel: 0, isMuted: false), for: ids, "Reset clip levels")
        }) {
            InspectorToggle(title: "Mute", value: model.sharedClipValue(\.isMuted)) { model.setMuted($0, for: ids) }
                .frame(height: 22)
            if !mics.isEmpty {
                InspectorSlider(title: "Voice", value: model.sharedClipValue(\.voiceLevel), range: SoundLevel.range, unit: "dB") {
                    model.setSound(.init(voiceLevel: $0), for: ids)
                }
            }
            if hasSystem {
                InspectorSlider(title: "System", value: model.sharedClipValue(\.systemAudioLevel), range: SoundLevel.range, unit: "dB") {
                    model.setSound(.init(systemAudioLevel: $0), for: ids)
                }
            }
            if mics.isEmpty, !hasSystem { detail("These clips have no recorded audio.") }
        }
        if let project = model.project, project.sources.filter({ $0.primaryAudioTrack != nil }).count > 1 {
            InspectorSection("Audio source", expanded: false) {
                InspectorRow("Microphone") {
                    Picker("Microphone", selection: Binding(get: { ClipAudioChoice(clips: clips) }, set: { choice in
                        switch choice {
                        case .mixed: break
                        case .own: model.setAudio(nil, for: ids)
                        case .track(let audio): model.setAudio(audio, for: ids)
                        }
                    })) {
                        if ClipAudioChoice(clips: clips) == .mixed { Text("Mixed").tag(ClipAudioChoice.mixed) }
                        Text("Own microphone").tag(ClipAudioChoice.own)
                        ForEach(project.sources.filter { source in source.primaryAudioTrack != nil && clips.contains { $0.source != source.id } }, id: \.id) { source in
                            if let track = source.primaryAudioTrack {
                                Text(source.name).tag(ClipAudioChoice.track(ClipAudio(source: source.id, track: track.kind)))
                            }
                        }
                    }
                    .labelsHidden()
                }
            }
        }
        ForEach(mics, id: \.id) { source in
            TakeAudioInspector(model: model, source: source)
        }
        InspectorSection("Loudness preview", expanded: false) { LoudnessPreviewControls(model: model, showsTitle: false) }
    }
}

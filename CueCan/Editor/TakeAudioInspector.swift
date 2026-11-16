import ProjectKit
import SwiftUI

struct TakeAudioInspector: View {
    let model: EditorModel
    let source: Source
    @Environment(AppModel.self) private var app

    var body: some View {
        let settings = model.edit?.audio.settings(for: source.id) ?? SourceAudioSettings()
        InspectorSection(title, summary: source.name,
                         storageKey: "takeAudio.\(source.id)",
                         canReset: settings != SourceAudioSettings(), reset: {
            model.setVoice(for: source.id, "Reset Cleanup and Voice", processing: app.processing) { $0 = SourceAudioSettings() }
        }) {
            VoiceControls(model: model, processing: app.processing, source: source)
        }
        .help("Applies to every clip from \(source.name).")
    }

    private var title: String {
        let microphones = model.project?.sources.filter { $0.primaryAudioTrack != nil }.count ?? 0
        return microphones > 1 ? source.name : "Microphone"
    }
}

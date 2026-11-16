import ProjectKit
import SwiftUI

/// Cleanup and Voice are processed once for a take; these controls never change DSP or clip levels.
struct VoiceControls: View {
    let model: EditorModel
    let processing: ProcessingCenter
    let source: Source

    var body: some View {
        let settings = model.edit?.audio.settings(for: source.id) ?? SourceAudioSettings()
        InspectorRow("Cleanup") {
            Picker("Cleanup", selection: Binding(get: { settings.cleanup.mode }, set: { mode in
                model.setVoice(for: source.id, "Cleanup \(mode.rawValue)", processing: processing) { $0.cleanup.mode = mode }
            })) {
                Text("Off").tag(CleanupSettings.Mode.off)
                Text("Natural").tag(CleanupSettings.Mode.natural)
            }
            .labelsHidden()
        }
        if settings.cleanup.mode == .natural {
            AudioAmountButtons(title: "Cleanup amount", value: settings.cleanup.amount) { amount in
                model.setVoice(for: source.id, "Cleanup \(Int(amount))%", processing: processing) { $0.cleanup.amount = amount }
            }
        }
        InspectorRow("Voice") {
            Picker("Voice", selection: Binding(get: { settings.voice.preset }, set: { preset in
                model.setVoice(for: source.id, "Voice \(preset.rawValue)", processing: processing) { $0.voice.preset = preset }
            })) {
                Text("Off").tag(VoiceSettings.Preset.off)
                Text("Clear").tag(VoiceSettings.Preset.clear)
                Text("Broadcast").tag(VoiceSettings.Preset.broadcast)
            }
            .labelsHidden()
        }
        if settings.voice.preset != .off {
            AudioAmountButtons(title: "Voice amount", value: settings.voice.amount) { amount in
                model.setVoice(for: source.id, "Voice \(Int(amount))%", processing: processing) { $0.voice.amount = amount }
            }
        }
    }
}

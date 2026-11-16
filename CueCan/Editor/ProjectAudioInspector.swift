import ProjectKit
import SwiftUI

struct ProjectAudioInspector: View {
    let model: EditorModel

    var body: some View {
        let mics = model.playedMics
        ForEach(mics, id: \.id) { source in
            TakeAudioInspector(model: model, source: source)
        }
        InspectorSection("Loudness preview") { LoudnessPreviewControls(model: model, showsTitle: false) }
        if mics.isEmpty {
            ContentUnavailableView("No microphone audio", systemImage: "mic.slash")
        }
    }
}

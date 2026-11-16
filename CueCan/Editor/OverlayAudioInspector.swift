import ProjectKit
import SwiftUI

struct OverlayAudioInspector: View {
    let model: EditorModel
    let overlay: Overlay

    var body: some View {
        if overlay.isStill {
            InspectorSection("Audio") { detail("Still images have no audio.") }
        } else {
            InspectorSection("Levels", canReset: !overlay.isMuted || overlay.level != 0, reset: {
                model.updateOverlay(overlay.id, "Reset overlay audio") { $0.isMuted = true; $0.level = 0 }
            }) {
                InspectorToggle(title: "Mute", value: overlay.isMuted) { muted in
                    model.updateOverlay(overlay.id, muted ? "Muted overlay" : "Unmuted overlay") { $0.isMuted = muted }
                }
                .frame(height: 22)
                InspectorSlider(title: "Level", value: overlay.level, range: SoundLevel.range, unit: "dB") {
                    model.setLevel($0, forOverlay: overlay.id)
                }
                detail("Video overlays start muted.")
            }
        }
    }
}

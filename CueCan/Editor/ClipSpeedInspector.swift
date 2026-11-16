import ProjectKit
import SwiftUI

/// Speed controls explicitly represent a mixed selection instead of inheriting the first clip's value.
struct ClipSpeedInspector: View {
    let model: EditorModel
    let ids: Set<ClipID>

    var body: some View {
        let clips = model.edit?.main.filter { ids.contains($0.id) } ?? []
        let values = ClipSpeedSelection(clips: clips)
        InspectorSection("Speed", summary: values.rate.flatMap { ClipSpeed(rate: $0)?.label } ?? "Mixed",
                         expanded: clips.contains { !$0.speed.isNormal },
                         canReset: clips.contains { !$0.speed.isNormal }, reset: { model.setSpeed(.normal, for: ids) }) {
            InspectorRow("Rate") {
                Picker("Speed", selection: Binding(get: { values.rate }, set: { rate in
                    if let rate, let speed = ClipSpeed(rate: rate) { model.setSpeed(speed, for: ids) }
                })) {
                    if values.rate == nil { Text("Mixed").tag(nil as Double?) }
                    ForEach(ClipSpeed.rates, id: \.self) { rate in
                        Text(ClipSpeed(rate: rate)?.label ?? "").tag(Optional(rate))
                    }
                }
                .labelsHidden()
            }
            if clips.contains(where: { !$0.speed.isNormal }) {
                InspectorRow("Audio") {
                    Picker("Retimed audio", selection: Binding(get: { values.sound }, set: { sound in
                        if let sound { model.setSpeedSound(sound, for: ids) }
                    })) {
                        if values.sound == nil { Text("Mixed").tag(nil as ClipSpeed.Sound?) }
                        Text("Keep pitch").tag(Optional(ClipSpeed.Sound.pitchKept))
                        Text("Mute").tag(Optional(ClipSpeed.Sound.muted))
                    }
                    .labelsHidden()
                }
            }
        }
    }
}

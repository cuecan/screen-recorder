import ProjectKit
import SwiftUI

/// The audio lane's header (docs/ui.md, E6): the lane's name, and which waveform is which. Its controls are
/// in the tool strip (``AudioTools``).
struct AudioLaneHeader: View {
    let model: EditorModel

    var body: some View {
        let hasSystemAudio = model.project?.sources.contains { $0.track(.systemAudio) != nil } ?? false
        VStack(alignment: .leading, spacing: 4) {
            Text("Audio").font(.caption).foregroundStyle(.secondary)
            if hasSystemAudio {
                VStack(alignment: .leading, spacing: 1) {
                    key("Voice", .green)
                    key("System", .gray)
                }
                .font(.system(size: 9))
                .fixedSize()
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func key(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 6, height: 6)
            Text(name)
        }
        .accessibilityElement(children: .combine)
    }
}

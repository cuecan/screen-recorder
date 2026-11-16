import SwiftUI

/// A small rounded label, such as "Transcribed" on a project card.
struct StatusChip: View {
    let title: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

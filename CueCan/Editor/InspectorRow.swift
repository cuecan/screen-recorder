import SwiftUI

/// Keeps parameter labels and values aligned across the video, audio and project inspectors.
struct InspectorRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ContentBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
                .lineLimit(1)
            content
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .frame(minHeight: 24)
    }
}

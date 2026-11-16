import SwiftUI

/// A compact, collapsible inspector group. Reset belongs beside the section it affects.
struct InspectorSection<Content: View>: View {
    let title: String
    var summary: String? = nil
    var canReset = false
    var reset: (() -> Void)? = nil
    let content: Content
    @SceneStorage private var isExpanded: Bool

    init(_ title: String, summary: String? = nil, expanded: Bool = true, storageKey: String? = nil,
         canReset: Bool = false, reset: (() -> Void)? = nil, @ContentBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.canReset = canReset
        self.reset = reset
        self.content = content()
        _isExpanded = SceneStorage(wrappedValue: expanded, "editor.inspector.section.\(storageKey ?? title)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(title).font(.callout.weight(.semibold))
                        Spacer(minLength: 0)
                        if !isExpanded, let summary {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(isExpanded ? "expanded" : "collapsed")")
                .help(isExpanded ? "Hide \(title.lowercased()) controls" : "Show \(title.lowercased()) controls")
                if let reset {
                    Button("Reset \(title.lowercased())", systemImage: "arrow.counterclockwise", action: reset)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(!canReset)
                        .help("Reset \(title.lowercased())")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(.quaternary.opacity(0.45))
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            Divider()
        }
    }
}

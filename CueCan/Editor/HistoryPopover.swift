import ProjectKit
import SwiftUI

/// History (docs/ui.md, E1): every change, yours and Claude's, newest first, with Undo to here.
struct HistoryPopover: View {
    let model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History").font(.headline).padding(12)
            Divider()
            if model.history.isEmpty {
                Text("No changes yet.").foregroundStyle(.secondary).padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.history.reversed(), id: \.sequence) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: entry.author.symbol)
                                    .foregroundStyle(entry.author.color)
                                    .help(entry.author.displayName)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.reason).lineLimit(2)
                                    Text("\(entry.author.displayName) · \(entry.savedAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Undo to here") { model.undo(through: entry.sequence) }
                                    .controlSize(.small)
                                    .accessibilityLabel("Undo \(entry.reason)")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .contain)
                            Divider().padding(.leading, 30)
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 420)
    }
}

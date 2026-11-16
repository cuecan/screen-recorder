import ProjectKit
import SwiftUI

/// Processing belongs to the take, so its progress and failures remain visible in every inspector tab.
struct EditorProcessingStatus: View {
    let folder: ProjectFolder
    let processing: ProcessingCenter

    var body: some View {
        if let activity = processing.activity[folder.url] {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(activity).lineLimit(1).help(activity)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
            .background(.regularMaterial, in: .rect(cornerRadius: 8))
        } else if let problem = processing.problems[folder.url] {
            HStack(spacing: 8) {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .lineLimit(2).help(problem)
                Button("Retry processing") { processing.process(folder) }
            }
            .font(.callout)
            .padding(10)
            .background(.regularMaterial, in: .rect(cornerRadius: 8))
        }
    }
}

import AppKit
import ProjectKit
import SwiftUI

/// Opens a selected project once. Opening failures are actionable, rather than looking as if the
/// creator never selected a take; sidebar refreshes don't reopen the project on the main thread.
struct ProjectDetailView: View {
    let url: URL
    @State private var state = ProjectOpenState.opening
    @State private var attempt = 0

    var body: some View {
        Group {
            switch state {
            case .opened(let folder):
                EditorView(folder: folder)
            case .failed(let problem):
                ContentUnavailableView {
                    Label("Couldn’t open this recording", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(problem).textSelection(.enabled)
                } actions: {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Retry") { attempt += 1 }
                }
            case .opening:
                ProgressView("Opening…")
            }
        }
        .task(id: attempt) {
            state = .opening
            do {
                let url = url
                let opened = try await Task.detached { try ProjectFolder(opening: url) }.value
                guard !Task.isCancelled else { return }
                state = .opened(opened)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }
}

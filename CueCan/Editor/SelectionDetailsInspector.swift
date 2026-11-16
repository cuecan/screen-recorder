import AppKit
import ProjectKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - An overlay

struct OverlayInspector: View {
    let model: EditorModel
    let overlay: Overlay

    var body: some View {
        if model.inspectorTab == .audio {
            OverlayAudioInspector(model: model, overlay: overlay)
        } else {
            InspectorSection("Overlay", summary: model.displayName(of: overlay)) {
                if case .file(let file, true) = overlay.media, let image = NSImage(contentsOf: file.url(relativeTo: model.folder.url)) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 120).clipShape(.rect(cornerRadius: 6))
                }
                Text(model.displayName(of: overlay)).font(.callout.weight(.semibold)).textSelection(.enabled)
                InspectorRow("Placement") {
                    Picker("Overlay placement", selection: Binding(get: { overlay.placement }, set: { placement in
                        model.updateOverlay(overlay.id, placement.label) { $0.placement = placement }
                    })) {
                        ForEach(Overlay.Placement.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                detail(overlay.placement == .coversFrame ? "Hides the screen and camera." : "Keeps the camera in the layout.")
            }
            InspectorSection("Anchor") {
                Text(anchorText).font(.callout)
            }
            InspectorSection("Media", expanded: false) {
                HStack {
                    Button("Replace…") {
                        if let url = OverlayFiles.choose() { model.replaceOverlay(overlay.id, with: url) }
                    }
                    Button("Remove overlay", role: .destructive) {
                        model.selection = .overlays([overlay.id])
                        model.deleteSelection()
                    }
                }
            }
        }
    }

    private var anchorText: String {
        switch overlay.over {
        case .words(let range):
            let text = model.text(of: range)
            return "“\(text.count > 80 ? String(text.prefix(80)) + "…" : text)”"
        case .time(let source, let range):
            let name = model.project?.source(source)?.name ?? "Recording"
            return "\(name) · \(model.clock(range.start)) – \(model.clock(range.end))"
        }
    }
}

/// Choosing a picture or a video to put on top.
enum OverlayFiles {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.canChooseDirectories = false
        panel.message = "Choose a picture or a video to put on top"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - A freeze

struct FreezeInspector: View {
    let model: EditorModel
    let freeze: Freeze

    var body: some View {
        InspectorSection("Hold") {
            if model.inspectorTab == .audio {
                detail("A hold only changes the picture.")
                if let clip = model.edit?.clip(holding: freeze) {
                    Button("Inspect clip audio") { model.selectClip(clip.id); model.inspectorTab = .audio }
                }
            } else {
                InspectorRow("Held frame") { Text(model.clock(freeze.frame)).monospacedDigit() }
                Button("Remove hold", role: .destructive) { model.deleteSelection() }
            }
        }
    }
}

extension Color {
    /// A colour from `#RRGGBB`.
    init(hex: String) {
        let look = OutputLook(background: hex)
        let parts = look.backgroundComponents
        self.init(red: parts.red, green: parts.green, blue: parts.blue)
    }

    /// `#RRGGBB`, in sRGB.
    var hex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}

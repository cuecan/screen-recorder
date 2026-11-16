import ProjectKit
import SwiftUI

struct BackgroundInspector: View {
    let model: EditorModel
    private static let swatches: [(name: String, hex: String)] = [
        ("Black", "#000000"), ("Graphite", "#1E1E20"), ("Light grey", "#D9D9D9"),
        ("White", "#FFFFFF"), ("Sand", "#F2E8DC"), ("Blue", "#203A5C"),
    ]

    var body: some View {
        let look = model.edit?.look ?? EditLook()
        InspectorSection("Background", summary: look.backdrop.label,
                         canReset: !look.hasStartingBackground, reset: {
            model.setLook("Reset background") { $0.resetBackground() }
        }) {
            InspectorRow("Backdrop") {
                Picker("Backdrop", selection: Binding(get: { look.backdrop }, set: { backdrop in
                    model.setLook("\(backdrop.label) backdrop") { $0.choose(backdrop) }
                })) {
                    Text(OutputLook.Backdrop.plain.label).tag(OutputLook.Backdrop.plain)
                    Section("Light") {
                        ForEach(OutputLook.Backdrop.allCases.filter { $0.isPreset && !$0.isDark }, id: \.self) { Text($0.label).tag($0) }
                    }
                    Section("Dark") {
                        ForEach(OutputLook.Backdrop.allCases.filter(\.isDark), id: \.self) { Text($0.label).tag($0) }
                    }
                }
                .labelsHidden()
            }
            if look.backdrop == .plain {
                InspectorRow("Colour") {
                    HStack(spacing: 7) {
                        ForEach(Self.swatches, id: \.hex) { swatch in
                            Button {
                                set(swatch.hex)
                            } label: {
                                Circle().fill(Color(hex: swatch.hex)).frame(width: 17, height: 17)
                                    .overlay(Circle().strokeBorder(look.background.caseInsensitiveCompare(swatch.hex) == .orderedSame ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(swatch.name) background")
                            .accessibilityAddTraits(look.background.caseInsensitiveCompare(swatch.hex) == .orderedSame ? .isSelected : [])
                            .help(swatch.name)
                        }
                        Button("Custom background colour", systemImage: "plus.circle") {
                            BackgroundColorPanel.shared.open(look.background, onChoose: set)
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Choose a custom colour")
                    }
                }
            }
            ForEach(OutputLook.AddOn.allCases, id: \.self) { addOn in
                InspectorToggle(title: addOn.label, value: look.addOns.contains(addOn)) { on in
                    model.setLook("\(addOn.label) \(on ? "on" : "off")") { look in
                        if on { look.addOns.insert(addOn) } else { look.addOns.remove(addOn) }
                    }
                }
                .frame(height: 22)
            }
        }
        .onDisappear { BackgroundColorPanel.shared.close() }
    }

    private func set(_ colour: String) { model.setLook("Background \(colour)") { $0.background = colour } }
}

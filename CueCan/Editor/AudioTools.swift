import AppKit
import ProjectKit
import SwiftUI

/// The tool strip's audio group (docs/ui.md, E6; docs/ui/mockups/EditorAudioTools.html): Normalize, Noise
/// reduction and Equalizer. Each is a switch, drawn like Snapping: the accent colour while on, faint while
/// off. A click switches it; a right-click, or a click held, opens its settings under it.
struct AudioTools: View {
    let model: EditorModel
    let width: CGFloat
    let height: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 2) {
            normalize
            switchButton(.noiseReduction, icon: .noiseReduction, popover: .noiseReduction)
            switchButton(.equalizer, icon: .equalizer, popover: .equalizer)
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .disabled(model.timeline == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio")
    }

    /// Plays at the export's loudness. It changes what's heard here, never the edit.
    @ViewBuilder private var normalize: some View {
        let state = model.previewLoudness.state
        let failure: String? = if case .failed(_, let message) = state { message } else { nil }
        AudioToolButton(icon: .normalize, isOn: model.normalizePreview, isBusy: model.previewLoudness.isPreparing,
                        hasProblem: failure != nil, width: width, height: height,
                        title: "Normalize",
                        help: failure.map { "Couldn’t normalize playback: \($0) Click to try again." }
                            ?? "Normalize, \(model.normalizePreview ? "on" : "off")",
                        toggle: {
                            if failure != nil { model.retryNormalizedPreview() } else { model.normalizePreview.toggle() }
                        }, openSettings: nil)
    }

    private func switchButton(_ audioSwitch: AudioSwitch, icon: AudioToolIcon.Kind, popover: InspectorPopover) -> some View {
        let isOn = model.isOn(audioSwitch)
        let hasMicrophone = !model.playedMics.isEmpty
        return AudioToolButton(icon: icon, isOn: isOn, isBusy: false, hasProblem: false, width: width, height: height,
                               title: audioSwitch.title,
                               help: hasMicrophone ? "\(audioSwitch.title), \(isOn ? "on" : "off")" : "This edit has no microphone audio.",
                               toggle: { model.toggle(audioSwitch, processing: app.processing) },
                               openSettings: { model.inspectorPopover = popover })
            .disabled(!hasMicrophone)
            .popover(isPresented: model.presentation(of: popover), arrowEdge: .bottom) {
                AudioSwitchSettings(model: model, audioSwitch: audioSwitch, processing: app.processing)
            }
    }
}

/// One audio switch. Not a `Button`: a held click opens the settings, and mustn't also switch it.
private struct AudioToolButton: View {
    let icon: AudioToolIcon.Kind
    let isOn: Bool
    let isBusy: Bool
    let hasProblem: Bool
    let width: CGFloat
    let height: CGFloat
    let title: String
    let help: String
    let toggle: () -> Void
    let openSettings: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView().controlSize(.mini)
            } else {
                AudioToolIcon(kind: icon).frame(width: 16, height: 15)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .foregroundStyle(hasProblem ? AnyShapeStyle(Color.orange) : isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        .opacity(isEnabled ? 1 : 0.5)
        .onTapGesture { if isEnabled { toggle() } }
        .onLongPressGesture(minimumDuration: 0.4) { if isEnabled { openSettings?() } }
        .overlay { if let openSettings, isEnabled { SecondaryClickCatcher(action: openSettings) } }
        .help(help)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if isEnabled { toggle() } }
        .accessibilityActions {
            if let openSettings {
                Button("Settings") { if isEnabled { openSettings() } }
            }
        }
    }
}

/// A switch's own settings, for each mic the edit plays: the equalizer's preset and amount, or noise
/// reduction's amount. The same settings are in the inspector's Audio tab.
private struct AudioSwitchSettings: View {
    let model: EditorModel
    let audioSwitch: AudioSwitch
    let processing: ProcessingCenter

    var body: some View {
        let mics = model.playedMics
        VStack(alignment: .leading, spacing: 10) {
            Text(audioSwitch.title).font(.callout.weight(.semibold))
            ForEach(mics, id: \.id) { source in
                let settings = model.edit?.audio.settings(for: source.id) ?? SourceAudioSettings()
                VStack(alignment: .leading, spacing: 6) {
                    if mics.count > 1 { Text(source.name).font(.caption).foregroundStyle(.secondary) }
                    switch audioSwitch {
                    case .equalizer:
                        Picker("Preset", selection: Binding(get: { settings.voice.preset == .off ? nil : settings.voice.preset }, set: { preset in
                            guard let preset else { return }
                            model.setVoice(for: source.id, "Voice \(preset.rawValue)", processing: processing) { $0.voice.preset = preset }
                        })) {
                            Text("Clear").tag(Optional(VoiceSettings.Preset.clear))
                            Text("Broadcast").tag(Optional(VoiceSettings.Preset.broadcast))
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        AudioAmountButtons(title: "Equalizer amount", value: settings.voice.amount, showsTitle: false) { amount in
                            model.setVoice(for: source.id, "Voice \(Int(amount))%", processing: processing) { $0.voice.amount = amount }
                        }
                    case .noiseReduction:
                        AudioAmountButtons(title: "Noise reduction amount", value: settings.cleanup.amount, showsTitle: false) { amount in
                            model.setVoice(for: source.id, "Cleanup \(Int(amount))%", processing: processing) { $0.cleanup.amount = amount }
                        }
                    }
                }
            }
        }
        .controlSize(.small)
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }
}

/// The three audio icons, drawn to match the strip's line weight (docs/ui/mockups/EditorAudioTools.html).
struct AudioToolIcon: View {
    enum Kind { case normalize, noiseReduction, equalizer }
    let kind: Kind

    var body: some View {
        Canvas { context, size in
            // Drawn in a 16 × 15 box.
            context.scaleBy(x: size.width / 16, y: size.height / 15)
            let line = StrokeStyle(lineWidth: 1.3, lineCap: .round)
            func stroke(_ points: [(CGFloat, CGFloat, CGFloat, CGFloat)], style: StrokeStyle = line) {
                var path = Path()
                for (x1, y1, x2, y2) in points {
                    path.move(to: CGPoint(x: x1, y: y1))
                    path.addLine(to: CGPoint(x: x2, y: y2))
                }
                context.stroke(path, with: .foreground, style: style)
            }
            switch kind {
            case .normalize:
                // Bars brought up to one line.
                stroke([(2, 3, 14, 3), (4, 6, 4, 13), (8, 6, 8, 13), (12, 6, 12, 13)])
            case .noiseReduction:
                // A waveform with its noise struck out.
                stroke([(2.5, 6, 2.5, 9), (5.2, 3.5, 5.2, 11.5), (7.9, 5, 7.9, 10), (10.6, 2.5, 10.6, 12.5)])
                stroke([(12.2, 12.2, 14.8, 9.6), (12.2, 9.6, 14.8, 12.2)], style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case .equalizer:
                // Three sliders. Each knob is a ring, with the track cut where it sits.
                let knobs: [(CGFloat, CGFloat)] = [(3.5, 9.5), (8, 5), (12.5, 8)]
                for (x, y) in knobs {
                    stroke([(x, 2, x, y - 2.3), (x, y + 2.3, x, 13)])
                    context.stroke(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: .foreground, lineWidth: 1.3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Catches a right-click on what it covers and lets every other click through.
private struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.action = action
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) { view.action = action }

    final class Catcher: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { action?() }
    }
}

extension EditorModel {
    /// The mics the edit plays, each once, in the order the project lists them.
    var playedMics: [Source] {
        let played = Set(edit?.main.map { $0.audio?.source ?? $0.source } ?? [])
        return project?.sources.filter { $0.primaryAudioTrack != nil && played.contains($0.id) } ?? []
    }

    /// Whether every mic the edit plays has this on.
    func isOn(_ audioSwitch: AudioSwitch) -> Bool {
        guard let edit else { return false }
        return audioSwitch.isOn(for: playedMics.map(\.id), in: edit.audio)
    }

    /// Switches it for every mic the edit plays, as one change, then processes the voice again.
    func toggle(_ audioSwitch: AudioSwitch, processing: ProcessingCenter) {
        let mics = playedMics.map(\.id)
        guard !mics.isEmpty, let audio = edit?.audio else { return }
        let on = !audioSwitch.isOn(for: mics, in: audio)
        if audioSwitch == .equalizer, !on {
            // So switching it back on brings back Broadcast where that was chosen.
            for mic in mics where audio.settings(for: mic).voice.preset != .off {
                lastVoicePresets[mic] = audio.settings(for: mic).voice.preset
            }
        }
        let presets = lastVoicePresets
        var changed = false
        if change("\(audioSwitch.title) \(on ? "on" : "off")", { edit, _ in
            changed = edit.audio.set(audioSwitch, on: on, for: mics, restoring: presets)
        }), changed {
            processing.process(folder)
        }
    }
}

import ProjectKit
import RecorderKit
import RenderKit
import SwiftUI

/// The Recording Panel during a take (docs/ui.md, R6; docs/decisions.md, 18, 50, 51 and 82): one panel,
/// resizable, showing the preview of the export or the camera alone. The width sets the picture's size; the
/// header, mic row and controls keep theirs. It proves each source is really recording and holds the
/// controls. While setting up, the setup element shows the preview instead (docs/decisions.md, 79).
///
/// Both views are always built, the one not shown see-through, so the toggle and resizing only move and
/// resize the camera's preview layers: a new `AVCaptureVideoPreviewLayer` on the running session rebuilds
/// its capture graph and leaves a gap in the recorded camera (docs/ui.md, R6).
struct RecordingPanelView: View {
    let recorder: RecorderModel
    let shows: RecordingPanelShows
    let width: Double
    /// Below 260 pt, the format, the mic's name and the buttons' words drop.
    let isNarrow: Bool
    @State private var discard = MenuAnchor()

    var body: some View {
        let status = PanelStatus(recorder: recorder)
        let inner = max(RecordingPanelLayout.minimumWidth, width) - 2 * RecordingPanelLayout.padding
        let tileHeight = RecordingPanelLayout.previewTileHeight(contentWidth: inner, destination: recorder.destination)
        let showsCamera = shows == .camera && recorder.isCameraOn
        VStack(spacing: RecordingPanelLayout.spacing) {
            header(status)

            ZStack(alignment: .top) {
                ExportPreviewView(recorder: recorder, height: tileHeight, isFloating: true, screenIsVisible: !showsCamera)
                    .frame(width: inner)
                    .opacity(showsCamera ? 0 : 1)
                    .allowsHitTesting(!showsCamera)
                    .accessibilityHidden(showsCamera)
                if recorder.isCameraOn {
                    CameraOnlyView(recorder: recorder, side: inner)
                        .opacity(showsCamera ? 1 : 0)
                        .allowsHitTesting(showsCamera)
                        .accessibilityHidden(!showsCamera)
                }
            }
            .frame(width: inner, height: showsCamera ? inner : tileHeight, alignment: .top)

            micRow

            if let problem = recorder.setupProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Dimmed until the take is recording.
            HStack(spacing: 8) {
                PanelButton(title: "Discard", systemImage: "trash", iconOnly: isNarrow) {
                    discard.openHUD(DiscardMenu.entries(recorder), edge: .above)
                }
                .background(MenuAnchorView(anchor: discard))
                .disabled(!recorder.canDiscard)
                PanelButton(title: status.paused ? "Resume" : "Pause", systemImage: status.paused ? "play.fill" : "pause.fill", iconOnly: isNarrow) {
                    recorder.togglePause()
                }
                .disabled(!recorder.canPause)
                StopButton(recorder: recorder, iconOnly: isNarrow)
            }
            .frame(height: RecordingPanelLayout.controlsHeight)
        }
        .padding(RecordingPanelLayout.padding)
        .frame(width: max(RecordingPanelLayout.minimumWidth, width))
        .foregroundStyle(.white)
        .hudBackground(cornerRadius: 14, movesWindow: true)
    }

    /// The dot, the state and the format, the timer, and the toggle. Everything but the toggle drags the
    /// panel: the status is plain text.
    private func header(_ status: PanelStatus) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                Circle().fill(status.dot).frame(width: 8, height: 8)
                Text(status.headline).fontWeight(.semibold).fixedSize()
                if !isNarrow {
                    Text(recorder.formatLabel)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if recorder.phase.showsElapsed {
                Text(status.timer).fontWeight(.semibold).monospacedDigit().fixedSize()
                    .allowsHitTesting(false)
            }
            PanelViewToggle(recorder: recorder, shows: shows)
        }
        .font(.system(size: 12))
        .frame(height: RecordingPanelLayout.headerHeight)
        .background(WindowDragArea())
    }

    /// The mic: its name and its meter, holding its peak; narrow, the meter fills the row. There's no
    /// waveform (docs/decisions.md, 18).
    private var micRow: some View {
        let inner = max(RecordingPanelLayout.minimumWidth, width) - 2 * RecordingPanelLayout.padding
        return HStack(spacing: 7) {
            if recorder.isMicOn {
                Image(systemName: "mic")
                    .font(.system(size: 11))
                if isNarrow {
                    LevelMeterView(decibels: recorder.meterDecibels, peak: recorder.meterPeakDecibels, height: 5)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(recorder.micName ?? "Mic")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LevelMeterView(decibels: recorder.meterDecibels, peak: recorder.meterPeakDecibels, height: 5)
                        .frame(width: min(160, (inner * 0.45).rounded()))
                }
            } else {
                MicOffIcon()
                Text(recorder.lostMic.map { "\($0.name) disconnected" } ?? "Mic off")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.62))
        .frame(height: RecordingPanelLayout.micRowHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recorder.isMicOn ? "Mic level, \(recorder.micName ?? "Mic")" : "Mic off")
    }
}

/// Camera only (docs/ui.md, R6): the camera in a square with 10 pt corners, cropped around the main camera
/// slot's framing point and zoom, the slot the setup's framing circle opens (R10), so it shows the face as
/// framed. It frames nothing itself, and drags the panel.
private struct CameraOnlyView: View {
    let recorder: RecorderModel
    let side: CGFloat

    var body: some View {
        let slot = recorder.formatCameraSlots.first ?? .fullScreen
        let crop = LayoutGeometry.framedCrop(source: recorder.cameraPictureSize, into: CGSize(width: side, height: side),
                                             framing: recorder.shownFraming(slot))
        // Mirrored as the main output's camera is, with the look's Mirror.
        let mirrored = recorder.format?.outputs.first.flatMap { output in
            recorder.previewFrame(in: output).placements.first { $0.cameraSlot == slot }?.mirrored
        } ?? false
        ZStack {
            CameraPreview(feed: recorder.cameraPreview, crop: crop)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            WindowDragArea()
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .accessibilityElement()
        .accessibilityLabel("The camera, as framed")
    }
}

/// The header's toggle (docs/ui.md, R6): a radio pair of icons, Preview of the export and Camera only,
/// named on hover. Camera only can't be picked with the camera off.
private struct PanelViewToggle: View {
    let recorder: RecorderModel
    let shows: RecordingPanelShows

    var body: some View {
        HStack(spacing: 2) {
            option(.preview, systemImage: "rectangle.inset.bottomright.filled", name: "Preview of the export", help: "Preview of the export")
            option(.camera, systemImage: "person.crop.square", name: "Camera only",
                   help: recorder.isCameraOn ? "Camera only" : "No camera to show", isEnabled: recorder.isCameraOn)
        }
        .padding(2)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show in the panel")
    }

    private func option(_ choice: RecordingPanelShows, systemImage: String, name: String, help: String, isEnabled: Bool = true) -> some View {
        let isOn = shows == choice && (choice == .preview || recorder.isCameraOn)
        return Button {
            recorder.panel.choose(choice == .camera ? .camera : .preview)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 24, height: 18)
                .background(isOn ? .white.opacity(0.26) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// What the panel's status says: Ready while setting up (a green dot, like the one macOS shows while the
/// camera is on), Recording (red) or Paused (amber) (docs/decisions.md, 50).
private struct PanelStatus {
    let recorder: RecorderModel

    var paused: Bool { recorder.phase == .paused }
    var headline: String { recorder.phase.statusTitle }
    var dot: Color {
        switch recorder.phase {
        case .idle, .settingUp: .green
        case .starting, .paused: .orange
        case .recording: .red
        case .saving, .discarding: .gray
        }
    }
    var timer: String { Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)) }
}

// MARK: - Parts

/// A crossed-out mic, where the meter would be when no mic is chosen.
private struct MicOffIcon: View {
    var body: some View {
        Image(systemName: "mic.slash")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .accessibilityLabel("Mic off")
    }
}

/// The two-item Discard menu: Start over, or Discard. Nothing else; clicking away or Esc closes it and the
/// recording carries on, and it never pauses (docs/decisions.md, 51).
enum DiscardMenu {
    static func entries(_ recorder: RecorderModel) -> [MenuEntry] {
        DiscardAction.allCases.map { action in
            .item(action.title, systemImage: action.systemImage, destructive: action.isDestructive) {
                action.perform(in: recorder)
            }
        }
    }
}

private struct StopButton: View {
    let recorder: RecorderModel
    let iconOnly: Bool

    var body: some View {
        Button {
            Task { await recorder.stop() }
        } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 9, height: 9)
                if !iconOnly { Text("Stop").fontWeight(.semibold) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Color.recordingRed, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!recorder.canStop)
        .help("Stop and save")
        .accessibilityLabel("Stop")
    }
}

/// Discard, and Pause or Resume: an icon and its word, or the icon alone in a narrow panel, named on hover.
private struct PanelButton: View {
    let title: String
    let systemImage: String
    let iconOnly: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    Image(systemName: systemImage)
                } else {
                    Label(title, systemImage: systemImage)
                }
            }
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.18)))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

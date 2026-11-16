import AppKit
import Carbon.HIToolbox
import ProjectKit

/// The shortcuts that work from any app (docs/ui.md, R1): New recording… (``RecordingCommand``), and
/// ⌃⌥⌘P to show or hide the Recording Panel. Registered with `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring access. They stay registered for the app's whole life.
final class GlobalHotKeys {
    /// A shortcut's key with ⌃⌥⌘, and what it does.
    private struct Shortcut {
        let keyCode: Int
        let action: @MainActor (AppModel) -> Void
    }

    private static let shortcuts = [
        Shortcut(keyCode: RecordingCommand.newRecording.keyCode) { RecordingCommand.newRecording.perform(in: $0) },
        Shortcut(keyCode: kVK_ANSI_P) { $0.recorder.panel.toggleShown() },
    ]

    private let app: AppModel
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init(app: AppModel) {
        self.app = app
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let index = Int(id.id)
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated {
                let keys = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
                guard GlobalHotKeys.shortcuts.indices.contains(index) else { return }
                GlobalHotKeys.shortcuts[index].action(keys.app)
            }
            return noErr
        }, 1, &type, context, &handler)

        let carbonModifiers = UInt32(controlKey | optionKey | cmdKey)
        for (index, command) in Self.shortcuts.enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4355_4341), id: UInt32(index)) // "CUCA"
            if RegisterEventHotKey(UInt32(command.keyCode), carbonModifiers, id, GetApplicationEventTarget(), 0, &reference) == noErr,
                let reference
            {
                references.append(reference)
            }
        }
    }
}

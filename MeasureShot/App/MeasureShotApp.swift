import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct MeasureShotApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("MeasureShot", id: "main") {
            EditorView()
                .environment(appState)
                .task {
                    GlobalHotKeyManager.shared.register {
                        Task { @MainActor in
                            appState.startCapture()
                        }
                    }
                }
        }
        .defaultSize(width: 1100, height: 760)

        MenuBarExtra("MeasureShot", systemImage: "ruler") {
            Button("Capture Region") {
                appState.startCapture()
            }
            .keyboardShortcut("4", modifiers: [.command, .option, .shift])

            Button("Open Editor") {
                appState.showEditor()
            }

            Divider()

            Button("Quit MeasureShot") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    func register(action: @escaping () -> Void) {
        guard hotKeyRef == nil else { return }
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let target = GetEventDispatcherTarget()

        InstallEventHandler(
            target,
            { _, event, _ in
                guard let event else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.id == 1 else {
                    return noErr
                }

                GlobalHotKeyManager.shared.action?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D534854), id: 1)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_4),
            UInt32(cmdKey | optionKey | shiftKey),
            hotKeyID,
            target,
            0,
            &hotKeyRef
        )
    }
}

import SwiftUI
import AppKit

/// Bouton qui capture la prochaine combinaison de touches.
public struct ShortcutRecorder: View {
    let controller: HotKeyController
    @State private var recording = false
    @State private var monitor: Any?
    @State private var invalid = false

    public init(controller: HotKeyController) { self.controller = controller }

    public var body: some View {
        Button { recording ? stop() : start() } label: {
            HStack(spacing: 8) {
                Image(systemName: recording ? "record.circle" : "keyboard")
                    .font(.system(size: 11, weight: .bold))
                    .symbolEffect(.pulse, isActive: recording)
                Text(recording ? (invalid ? "Ajoutez ⌘, ⌥ ou ⌃…" : "Tapez le raccourci…") : controller.shortcut.display)
                    .font(Theme.ui(14, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(recording ? .white : Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(minWidth: 170)
            .background(Capsule().fill(recording ? AnyShapeStyle(Theme.sea.gradient) : AnyShapeStyle(Theme.ink.opacity(0.06))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        controller.suspend()
        recording = true
        invalid = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { handle(event) }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard recording else { return false }
        if event.keyCode == 53 { stop(); return true } // Echap : annuler
        guard let shortcut = HotKeyShortcut(event: event) else {
            invalid = true
            NSSound.beep()
            return true
        }
        controller.shortcut = shortcut
        stop()
        return true
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { controller.apply() }
        recording = false
    }
}

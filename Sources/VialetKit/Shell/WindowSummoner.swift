import AppKit
import SwiftUI

/// Fait apparaitre / disparaitre la fenetre principale (identifiant `main`).
@MainActor
public enum WindowSummoner {
    /// Ouvre la fenetre principale si elle a ete fermee (fourni par `captureOpenWindow()`).
    public static var openMainWindow: (() -> Void)?
    /// Appele apres l'affichage quand on demande le focus (ex. placer le curseur dans un champ).
    public static var onFocus: (() -> Void)?

    public static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    public static func toggle() {
        if NSApp.isActive, let window = mainWindow, window.isKeyWindow, window.isVisible {
            NSApp.hide(nil)
        } else {
            show(focus: true)
        }
    }

    public static func show(focus: Bool = false) {
        NSApp.unhide(nil)
        NSApp.activate()
        if let window = mainWindow, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        if focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.runOnMainThread { onFocus?() }
            }
        }
    }
}

private struct CaptureOpenWindow: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { WindowSummoner.openMainWindow = { openWindow(id: "main") } }
    }
}

public extension View {
    /// Memorise l'action d'ouverture de la fenetre principale (`Window(id: "main")`).
    func captureOpenWindow() -> some View { modifier(CaptureOpenWindow()) }
}

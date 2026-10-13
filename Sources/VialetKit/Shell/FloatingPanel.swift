import AppKit
import SwiftUI
import Observation

/// Petite fenetre flottante, ouverte par le raccourci global. Panneau
/// "non activant" : on tape dedans sans que l'app passe au premier plan.
public final class FloatingPanel: NSPanel {
    /// Appele sur Echap ou quand le panneau perd le focus (clic ailleurs).
    public var onDismiss: (() -> Void)?

    public init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .utilityWindow
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func resignKey() {
        super.resignKey()
        onDismiss?()
    }

    public override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// Montre / cache un panneau flottant dont le contenu est une vue SwiftUI.
/// `openCount` s'incremente a chaque ouverture : la vue s'en sert pour
/// redonner le focus a son champ.
@MainActor
@Observable
public final class FloatingPanelController<Content: View> {
    public let size: CGSize
    public private(set) var openCount = 0
    private let content: () -> Content
    private var panel: FloatingPanel?

    public init(size: CGSize, @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.content = content
    }

    public var isVisible: Bool { panel?.isVisible == true }

    public func toggle() { isVisible ? hide() : show() }

    public func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        openCount += 1
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(size: size)
        panel.onDismiss = { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: content().fontDesign(.rounded))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }

    /// Centre horizontalement, au tiers haut de l'ecran ou se trouve la souris.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - size.width / 2,
                             y: frame.maxY - frame.height * 0.22 - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

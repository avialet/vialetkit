import AppKit
import SwiftUI
import Observation

/// Position d'un panneau flottant sur l'ecran de la souris, centre horizontalement.
public enum FloatingPanelPlacement: Equatable, Sendable {
    /// Haut du panneau a 22 % de la hauteur visible sous le haut de l'ecran (palette de saisie).
    case upperThird
    /// Bas du panneau a 10 % de la hauteur visible au-dessus du bas de l'ecran (panneau d'ecoute).
    case bottom

    /// Origine (coin bas gauche, coordonnees AppKit) du panneau de taille `size` dans `visibleFrame`.
    public func origin(in visibleFrame: CGRect, size: CGSize) -> CGPoint {
        let x = visibleFrame.midX - size.width / 2
        switch self {
        case .upperThird:
            return CGPoint(x: x, y: visibleFrame.maxY - visibleFrame.height * 0.22 - size.height)
        case .bottom:
            return CGPoint(x: x, y: visibleFrame.minY + visibleFrame.height * 0.10)
        }
    }
}

/// Petite fenetre flottante, ouverte par le raccourci global. Panneau
/// "non activant" : on tape dedans sans que l'app passe au premier plan.
/// Avec `takesFocus: false`, il ne devient jamais cle : il s'affiche au-dessus de l'app active
/// sans lui prendre la frappe, et ses boutons restent cliquables.
public final class FloatingPanel: NSPanel {
    /// Appele sur Echap ou quand le panneau perd le focus (clic ailleurs) ; jamais par la perte
    /// du focus si `takesFocus` est faux.
    public var onDismiss: (() -> Void)?
    /// Faux : le panneau ne devient jamais cle et ne se ferme pas quand une autre fenetre l'est.
    public let takesFocus: Bool

    public init(size: CGSize, takesFocus: Bool = true) {
        self.takesFocus = takesFocus
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

    public override var canBecomeKey: Bool { takesFocus }
    public override var canBecomeMain: Bool { false }

    public override func resignKey() {
        super.resignKey()
        if takesFocus { onDismiss?() }
    }

    public override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// Montre / cache un panneau flottant dont le contenu est une vue SwiftUI.
/// `openCount` s'incremente a chaque ouverture : la vue s'en sert pour
/// redonner le focus a son champ.
/// `takesFocus: false` : panneau d'ecoute qui s'affiche sans activer l'app ni devenir cle
/// (la frappe reste a l'app active) ; `placement` choisit le haut ou le bas de l'ecran.
@MainActor
@Observable
public final class FloatingPanelController<Content: View> {
    public let size: CGSize
    public let takesFocus: Bool
    public let placement: FloatingPanelPlacement
    public private(set) var openCount = 0
    private let content: () -> Content
    private var panel: FloatingPanel?

    public init(size: CGSize, takesFocus: Bool = true, placement: FloatingPanelPlacement = .upperThird,
                @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.takesFocus = takesFocus
        self.placement = placement
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
        if takesFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
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
        let panel = FloatingPanel(size: size, takesFocus: takesFocus)
        panel.onDismiss = { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: content().fontDesign(.rounded))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }

    /// Sur l'ecran ou se trouve la souris, selon `placement`.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = placement.origin(in: frame, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

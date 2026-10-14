import AppKit
import SwiftUI

/// L'icone vialet.app dans la barre des menus (plaque du hub en tons, point de mise a jour) et son
/// menu rassembleur : un panneau sous l'icone, au papier de vialet.app, ferme par Echap, un clic
/// ailleurs ou un second clic sur l'icone. Tenue par l'app Vialet, ou par l'app hote (`HubPresence`).
@MainActor
public final class HubStatusItem {
    public let model: HubModel
    public let options: HubMenuOptions
    private let toolTip: String
    private let autosaveName: String
    private var item: NSStatusItem?
    private let dot = CALayer()
    private var panel: FloatingPanel?
    private var host: NSHostingView<AnyView>?
    /// Fermeture par perte du focus juste avant un clic sur l'icone : ce clic ne rouvre pas.
    private var lastDismiss = Date.distantPast
    /// Jeton du suivi des mises a jour : un suivi d'une pose precedente (retiree puis reposee) s'eteint.
    private(set) var trackingGeneration = 0

    public var isOpen: Bool { panel?.isVisible == true }
    public var isInstalled: Bool { item != nil }

    /// `toolTip` : « vialet.app » (Vialet) ou qui tient le menu ; `autosaveName` garde la place de l'icone.
    public init(model: HubModel, options: HubMenuOptions = HubMenuOptions(), toolTip: String = "vialet.app",
                autosaveName: String = "Vialet") {
        self.model = model
        self.options = options
        self.toolTip = toolTip
        self.autosaveName = autosaveName
    }

    /// Pose l'icone (sans effet si elle y est).
    public func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.behavior = []
        item.autosaveName = autosaveName
        if let button = item.button {
            button.image = HubStatusIcon.image()
            button.imagePosition = .imageOnly
            button.toolTip = toolTip
            button.setAccessibilityLabel("Vialet")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.wantsLayer = true
            dot.backgroundColor = NSColor(hex: 0xEC6A5C).cgColor
            dot.cornerRadius = HubStatusIcon.dotDiameter / 2
            dot.isHidden = true
            button.layer?.addSublayer(dot)
        }
        self.item = item
        trackingGeneration += 1
        trackUpdates(generation: trackingGeneration)
    }

    /// Retire l'icone et ferme le menu (l'app n'est plus hote).
    public func remove() {
        close()
        panel?.orderOut(nil)
        panel = nil
        host = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        trackingGeneration += 1
    }

    /// Point de mise a jour : l'icone s'encoche, un point corail s'y pose (`Theme.coral`, la couleur
    /// des mises a jour dans les reglages des apps).
    private func trackUpdates(generation: Int) {
        guard item != nil, generation == trackingGeneration else { return }
        withObservationTracking {
            setDot(model.hasPendingUpdate)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackUpdates(generation: generation) }
        }
    }

    private func setDot(_ on: Bool) {
        guard let button = item?.button else { return }
        button.image = HubStatusIcon.image(notched: on)
        button.setAccessibilityLabel(on ? "Vialet, mise \u{00E0} jour disponible" : "Vialet")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.isHidden = !on
        // L'image (18 pt) est centree dans le bouton ; le point suit son coin haut droit.
        let bounds = button.bounds
        let origin = CGPoint(x: (bounds.width - HubStatusIcon.pointSize) / 2, y: (bounds.height - HubStatusIcon.pointSize) / 2)
        let d = HubStatusIcon.dotDiameter
        let centerY = button.isFlipped ? origin.y + (HubStatusIcon.pointSize - HubStatusIcon.dotCenter.y)
                                       : origin.y + HubStatusIcon.dotCenter.y
        dot.frame = CGRect(x: origin.x + HubStatusIcon.dotCenter.x - d / 2, y: centerY - d / 2, width: d, height: d)
        CATransaction.commit()
    }

    @objc private func clicked() { toggle() }

    public func toggle() {
        if isOpen { close(); return }
        guard Date().timeIntervalSince(lastDismiss) > 0.3 else { return }
        open()
    }

    public func open() {
        guard item != nil else { return }
        model.reload()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        resize()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        item?.button?.highlight(true)
    }

    public func close() {
        guard let panel, panel.isVisible else { return }
        lastDismiss = Date()
        panel.orderOut(nil)
        item?.button?.highlight(false)
    }

    /// Ferme le menu, puis lance `action` (ouvrir une app, un lien...).
    public func run(_ action: @escaping @MainActor () -> Void) {
        close()
        DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(size: CGSize(width: HubMenu.width, height: 200))
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.onDismiss = { [weak self] in self?.close() }
        let menu = HubMenu(model: model, options: options, run: { [weak self] action in self?.run(action) },
                           onSizeChange: { [weak self] in self?.resize() })
        let host = NSHostingView(rootView: AnyView(menu.fontDesign(.rounded)))
        panel.contentView = host
        self.host = host
        return panel
    }

    /// Taille ideale du contenu, sous l'icone (bord gauche aligne, comme un menu), dans l'ecran.
    private func resize() {
        guard let panel, let host else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var origin = CGPoint(x: 0, y: 0)
        if let window = item?.button?.window {
            let anchor = window.frame
            let screen = window.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? anchor
            origin.x = min(max(anchor.minX - 6, visible.minX + 6), visible.maxX - size.width - 6)
            origin.y = max(anchor.minY - 5 - size.height, visible.minY + 6)
        } else if let visible = NSScreen.main?.visibleFrame {
            origin = CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }
}

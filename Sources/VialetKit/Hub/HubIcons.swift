import AppKit

/// Icone de Vialet dans la barre des menus : la plaque du hub (un secteur par app, depuis midi dans
/// le sens horaire) en image template monochrome, dessinee en vectoriel (nette a 1x comme a 2x).
public enum HubStatusIcon {
    /// Les trois propositions de la planche (`-VialetSnapshotOnly icones`).
    public enum Variant: String, CaseIterable, Sendable {
        /// Plaque pleine decoupee en cinq secteurs par des jours.
        case secteurs
        /// Plaque en cinq secteurs de tons alternes : la plaque du hub en monochrome.
        case tons
        /// Grille 2 x 2 de petites plaques.
        case grille

        /// Retenue : la seule qui garde la plaque du hub (secteurs depuis midi) et sa lecture
        /// « plusieurs couleurs » sans dessin de plus ; les jours de `secteurs` font une etoile a
        /// 16 pt, `grille` se confond avec l'icone systeme des apps.
        public static let chosen: Variant = .tons
    }

    /// Cote du canevas (points) ; la plaque fait 14 pt (poids des symboles systeme), alignee sur la grille des pixels.
    public static let pointSize: CGFloat = 18
    static let plate = CGRect(x: 2, y: 2, width: 14, height: 14)
    /// Opacites des cinq secteurs de `tons`, depuis midi : voisins toujours distincts.
    public static let tones: [CGFloat] = [1.0, 0.5, 0.82, 0.32, 0.66]
    /// Point de mise a jour (coordonnees AppKit du canevas, y vers le haut) et son encoche.
    public static let dotCenter = CGPoint(x: 14.6, y: 14.6)
    public static let dotDiameter: CGFloat = 5
    static let notchRadius: CGFloat = 4.1

    /// Image template de 18 pt. `notched` : encoche transparente en haut a droite pour le point
    /// de mise a jour, pose a part en couleur.
    public static func image(_ variant: Variant = .chosen, notched: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(variant, in: ctx)
            if notched {
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: dotCenter.x - notchRadius, y: dotCenter.y - notchRadius,
                                           width: notchRadius * 2, height: notchRadius * 2))
                ctx.setBlendMode(.normal)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Vialet"
        return image
    }

    static func draw(_ variant: Variant, in ctx: CGContext) {
        let black = CGColor(gray: 0, alpha: 1)
        let center = CGPoint(x: plate.midX, y: plate.midY)
        let step = 2 * CGFloat.pi / 5
        switch variant {
        case .secteurs:
            ctx.addPath(plateShape(plate)); ctx.setFillColor(black); ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(1.3)
            for i in 0..<5 {
                let a = step * CGFloat(i)
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + 14 * sin(a), y: center.y + 14 * cos(a)))
            }
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2))
            ctx.setBlendMode(.normal)
        case .tons:
            ctx.saveGState()
            ctx.addPath(plateShape(plate)); ctx.clip()
            // Chaque secteur deborde un peu sur le suivant, qui le remplace (.copy) : pas de liseret.
            ctx.setBlendMode(.copy)
            for (i, alpha) in tones.enumerated() {
                ctx.addPath(sector(center: center, radius: 20, from: step * CGFloat(i), to: step * CGFloat(i + 1) + 0.03))
                ctx.setFillColor(CGColor(gray: 0, alpha: alpha)); ctx.fillPath()
            }
            ctx.restoreGState()
        case .grille:
            let side: CGFloat = 6, gap: CGFloat = 2
            for (i, j) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let r = CGRect(x: plate.minX + CGFloat(i) * (side + gap), y: plate.minY + CGFloat(j) * (side + gap),
                               width: side, height: side)
                ctx.addPath(plateShape(r)); ctx.setFillColor(black); ctx.fillPath()
            }
        }
    }

    /// Carre arrondi des plaques (rayon 185/824 du cote, comme scripts/plaque.swift).
    static func plateShape(_ r: CGRect) -> CGPath {
        let radius = r.width * 185 / 824
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// Secteur depuis midi, sens horaire, en coordonnees y vers le haut.
    static func sector(center: CGPoint, radius: CGFloat, from a0: CGFloat, to a1: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .pi / 2 - a0, endAngle: .pi / 2 - a1, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Plaque du hub en couleur : un secteur par app (teinte `background`), depuis midi dans le sens
/// horaire, comme le logo de vialet.app. Sans palette : plaque neutre.
public enum HubPlate {
    public static func image(_ palettes: [AccentPalette], pixels: Int) -> NSImage {
        let side = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: side, height: side))
        guard pixels > 0,
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.addPath(HubStatusIcon.plateShape(rect)); ctx.clip()
        if palettes.isEmpty {
            ctx.setFillColor(color(0x8A8F98)); ctx.fill(rect)
        } else {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let step = 2 * CGFloat.pi / CGFloat(palettes.count)
            for (i, p) in palettes.enumerated() {
                // Leger debord recouvert par le secteur suivant (comme scripts/plaque.swift hub).
                ctx.addPath(HubStatusIcon.sector(center: center, radius: side, from: step * CGFloat(i),
                                              to: step * CGFloat(i + 1) + 0.02))
                ctx.setFillColor(color(p.background)); ctx.fillPath()
            }
        }
        if let cg = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = image.size
            image.addRepresentation(rep)
        }
        return image
    }

    static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

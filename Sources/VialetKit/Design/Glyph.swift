import AppKit
import SwiftUI

// MARK: - Glyphe (copie de scripts/plaque.swift (depot vialetapps), garder identique)

public enum GlyphError: Error, CustomStringConvertible {
    case empty, command(String), arguments(String)
    public var description: String {
        switch self {
        case .empty: return "glyphe vide"
        case .command(let c): return "commande inconnue : \(c) (M L H V C Q Z absolus seulement)"
        case .arguments(let c): return "arguments manquants apres \(c)"
        }
    }
}

/// Trace d'un glyphe d'app (Brand.glyph) : sous-ensemble SVG absolu (M L H V C Q Z)
/// dans une boite 0-100, y vers le bas.
public enum GlyphPath {
    /// Le trace dans `rect` (coordonnees AppKit, y vers le haut).
    public static func cgPath(_ d: String, in rect: CGRect) throws -> CGPath {
        let path = try glyphPath(d)
        var t = CGAffineTransform(translationX: rect.minX, y: rect.maxY)
            .scaledBy(x: rect.width / 100, y: -rect.height / 100)
        return path.copy(using: &t) ?? path
    }

    /// Sous-ensemble SVG absolu (M L H V C Q Z) dans une boite 0-100, y vers le bas.
    static func glyphPath(_ d: String) throws -> CGPath {
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let path = CGMutablePath()
        var command: Character?
        var current = CGPoint.zero
        var start = CGPoint.zero
        var sawCommand = false
        func number() throws -> CGFloat {
            guard let v = scanner.scanDouble() else { throw GlyphError.arguments(String(command ?? "?")) }
            return CGFloat(v)
        }
        while !scanner.isAtEnd {
            if let letter = scanner.scanCharacter(), letter.isLetter {
                command = letter
                sawCommand = true
            } else if command != nil {
                scanner.currentIndex = d.index(before: scanner.currentIndex)
            }
            guard let c = command else { throw GlyphError.command(String(d.prefix(1))) }
            switch c {
            case "M":
                current = CGPoint(x: try number(), y: try number()); start = current; path.move(to: current); command = "L"
            case "L":
                current = CGPoint(x: try number(), y: try number()); path.addLine(to: current)
            case "H":
                current.x = try number(); path.addLine(to: current)
            case "V":
                current.y = try number(); path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: try number(), y: try number()), c2 = CGPoint(x: try number(), y: try number())
                current = CGPoint(x: try number(), y: try number()); path.addCurve(to: current, control1: c1, control2: c2)
            case "Q":
                let c1 = CGPoint(x: try number(), y: try number())
                current = CGPoint(x: try number(), y: try number()); path.addQuadCurve(to: current, control: c1)
            case "Z":
                path.closeSubpath(); current = start; command = nil
            default:
                throw GlyphError.command(String(c))
            }
        }
        guard sawCommand, !path.isEmpty else { throw GlyphError.empty }
        return path
    }
}

// MARK: - Images

/// Images tirees du glyphe : icone de barre des menus (template) et plaque d'app.
public enum GlyphImage {
    /// Glyphe en trait noir (bouts et jonctions ronds) dans 60 % d'un carre de `pointSize` points,
    /// en image template : la barre des menus la teinte en clair comme en sombre.
    /// Glyphe vide ou invalide : image transparente de la meme taille.
    public static func template(_ d: String, pointSize: CGFloat = 18, stroke: CGFloat = 1.7) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let box = CGRect(origin: .zero, size: size).insetBy(dx: pointSize * 0.20, dy: pointSize * 0.20)
        let path = try? GlyphPath.cgPath(d, in: box)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let path, let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Plaque plate de `pixels` cote (meme geometrie que drawPlate de scripts/plaque.swift,
    /// en mode plein et plat) : carre arrondi (rayon 22,45 %), fond accent ou blanc si `inverse`,
    /// glyphe en trait blanc, accent si `inverse`, deep si `strokeDeep`. Glyphe vide : sans trait.
    public static func plate(_ palette: AccentPalette, glyph: String, pixels: Int,
                             inverse: Bool = false, strokeDeep: Bool = false) -> NSImage {
        let side = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: side, height: side))
        guard pixels > 0,
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        let plate = CGRect(x: 0, y: 0, width: side, height: side)
        let radius = side * 185 / 824
        ctx.addPath(CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(inverse ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) : cgColor(palette.accent))
        ctx.fillPath()

        let box = plate.insetBy(dx: side * 0.20, dy: side * 0.20)
        if !glyph.isEmpty, let path = try? GlyphPath.cgPath(glyph, in: box) {
            let stroke = inverse ? cgColor(palette.accent)
                : (strokeDeep ? cgColor(palette.deep) : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.addPath(path)
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(box.width * 0.12)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
        if let cg = ctx.makeImage() {
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = image.size
            image.addRepresentation(rep)
        }
        return image
    }

    private static func cgColor(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Barre des menus

/// Label de `MenuBarExtra` : le glyphe de l'app en image template, qui suit le clair et le sombre
/// de la barre des menus.
public struct MenuBarIcon: View {
    let glyph: String
    let pointSize: CGFloat

    public init(glyph: String, pointSize: CGFloat = 18) {
        self.glyph = glyph
        self.pointSize = pointSize
    }

    public var body: some View {
        Image(nsImage: GlyphImage.template(glyph, pointSize: pointSize))
    }
}

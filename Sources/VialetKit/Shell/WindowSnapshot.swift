import AppKit

/// Rend le contenu d'une fenetre en PNG, par l'app elle-meme : utile pour les
/// captures de documentation et les verifications sans autorisation
/// d'enregistrement d'ecran. La barre de titre n'est pas incluse.
@MainActor
public enum WindowSnapshot {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    public static func write(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(description: "Fenêtre sans contenu à capturer.")
        }
        let image = try withWindowBackground(try render(view, into: rep), of: window)
        guard let data = image.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw Failure(description: "Encodage PNG impossible.")
        }
        try data.write(to: url)
    }

    /// `cacheDisplay` (comme `CALayer.render(in:)`) applique les ombres Core Animation (`.shadow` de SwiftUI)
    /// dans l'espace de base du contexte, sans tenir compte de la geometrie retournee des calques : l'ombre
    /// qui descend a l'ecran monte dans la capture. Pour une vue retournee (NSHostingView), on rend l'arbre
    /// de calques dans le contexte non retourne (contenu tete en bas, ombre vers le haut) puis on retourne
    /// l'image : contenu a l'endroit, ombre vers le bas. Les autres vues (panneau A propos d'AppKit) gardent
    /// `cacheDisplay`. Limite : une ombre de calque non retourne a l'interieur d'une vue SwiftUI serait inversee.
    private static func render(_ view: NSView, into rep: NSBitmapImageRep) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard view.isFlipped, let layer = view.layer, layer.isGeometryFlipped,
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep
        }
        layer.render(in: context.cgContext)
        context.flushGraphics()
        guard let upsideDown = rep.cgImage,
              let ctx = CGContext(data: nil, width: upsideDown.width, height: upsideDown.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "Rendu de la fen\u{00EA}tre impossible.")
        }
        ctx.translateBy(x: 0, y: CGFloat(upsideDown.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(upsideDown, in: CGRect(x: 0, y: 0, width: upsideDown.width, height: upsideDown.height))
        guard let upright = ctx.makeImage() else {
            throw Failure(description: "Rendu de la fen\u{00EA}tre impossible.")
        }
        let out = NSBitmapImageRep(cgImage: upright)
        out.size = rep.size
        return out
    }

    /// Le contenu pose sur le fond de la fenetre (`backgroundColor` dans son apparence) : les panneaux
    /// systeme (A propos) laissent ce fond au serveur de fenetres, absent du rendu. Fond transparent
    /// (panneau flottant) : rendu inchange.
    private static func withWindowBackground(_ rep: NSBitmapImageRep, of window: NSWindow) throws -> NSBitmapImageRep {
        guard let background = window.backgroundColor, background.alphaComponent > 0 else { return rep }
        var fill: CGColor?
        window.effectiveAppearance.performAsCurrentDrawingAppearance { fill = background.cgColor }
        guard let fill, let content = rep.cgImage,
              let ctx = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "Fond de fen\u{00EA}tre impossible \u{00E0} composer.")
        }
        let bounds = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        ctx.setFillColor(fill)
        ctx.fill(bounds)
        ctx.draw(content, in: bounds)
        guard let composed = ctx.makeImage() else {
            throw Failure(description: "Fond de fen\u{00EA}tre impossible \u{00E0} composer.")
        }
        let out = NSBitmapImageRep(cgImage: composed)
        out.size = rep.size
        return out
    }
}

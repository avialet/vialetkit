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
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = try withWindowBackground(rep, of: window)
        guard let data = image.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw Failure(description: "Encodage PNG impossible.")
        }
        try data.write(to: url)
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

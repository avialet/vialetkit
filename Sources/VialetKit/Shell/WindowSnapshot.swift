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
        guard let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw Failure(description: "Encodage PNG impossible.")
        }
        try data.write(to: url)
    }
}

import AppKit
import CoreText
import Foundation

/// Bricolage Grotesque embarquee dans le kit (donnees dans Fonts.swift, genere par
/// scripts/kit-fonts.sh). Pas de ressources SwiftPM : aucun .bundle a signer.
///
/// L'enregistrement en memoire (`CTFontManagerRegisterGraphicsFont`) est deprecie depuis
/// macOS 15 et `CTFontManagerRegisterFontDescriptors` refuse un descripteur sans URL
/// (erreur 303) : chaque police est donc ecrite une fois dans le dossier temporaire de
/// l'app, puis enregistree pour le processus par `CTFontManagerRegisterFontsForURL`.
@MainActor
enum Fonts {
    /// Noms PostScript (verifies sur les TTF avec CTFontManagerCreateFontDescriptorsFromURL).
    static let extraBoldName = "BricolageGrotesque96pt-ExtraBold"
    static let semiBoldName = "BricolageGrotesque-SemiBold"

    /// Vrai quand les deux polices sont utilisables ; sinon `Theme.display` reste en SF Rounded.
    static private(set) var registered = false

    static func register() {
        guard !registered else { return }
        let faces = [(extraBoldName, bricolageExtraBoldBase64), (semiBoldName, bricolageSemiBoldBase64)]
        registered = faces.allSatisfy { register(name: $0.0, base64: $0.1) }
    }

    private static func register(name: String, base64: String) -> Bool {
        if NSFont(name: name, size: 12) != nil { return true } // deja enregistree (ou installee)
        guard let data = Data(base64Encoded: base64), !data.isEmpty else {
            NSLog("VialetKit : police %@ illisible (base64)", name)
            return false
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VialetKitFonts", isDirectory: true)
        let url = dir.appendingPathComponent("\(name)-\(data.count).ttf")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            if size != data.count { try data.write(to: url, options: .atomic) }
        } catch {
            NSLog("VialetKit : police %@ non ecrite : %@", name, String(describing: error))
            return false
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let error {
            let cfError = error.takeRetainedValue()
            if CFErrorGetCode(cfError) != CTFontManagerError.alreadyRegistered.rawValue {
                NSLog("VialetKit : police %@ non enregistree : %@", name, String(describing: cfError))
            }
        }
        guard NSFont(name: name, size: 12) != nil else {
            NSLog("VialetKit : police %@ indisponible apres enregistrement", name)
            return false
        }
        return true
    }
}

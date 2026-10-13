import AppKit
import CoreText
import Foundation

/// Bricolage Grotesque embarquee dans le kit (donnees dans Fonts.swift, genere par
/// scripts/kit-fonts.sh). Pas de ressources SwiftPM : aucun .bundle a signer.
///
/// Pourquoi un fichier sur disque : l'enregistrement en memoire
/// (`CTFontManagerRegisterGraphicsFont`) est deprecie depuis macOS 15, cible du paquet, et
/// `CTFontManagerRegisterFontDescriptors` refuse un descripteur cree depuis des donnees, sans
/// URL (erreur 303, kCTFontManagerErrorInsufficientInfo). Chaque police est donc ecrite dans
/// les Caches de l'app (pas $TMPDIR, purge par macOS ; $TMPDIR seulement en repli), puis
/// enregistree pour le processus par `CTFontManagerRegisterFontsForURL`.
@MainActor
enum Fonts {
    /// Noms PostScript (verifies sur les TTF avec CTFontManagerCreateFontDescriptorsFromURL).
    nonisolated static let extraBoldName = "BricolageGrotesque96pt-ExtraBold"
    nonisolated static let semiBoldName = "BricolageGrotesque-SemiBold"

    /// Vrai quand les deux polices sont utilisables ; sinon `Theme.display` reste en SF Rounded.
    static private(set) var registered = false

    static func register() {
        guard !registered else { return }
        let faces = [(extraBoldName, bricolageExtraBoldBase64), (semiBoldName, bricolageSemiBoldBase64)]
        registered = faces.allSatisfy { register(name: $0.0, base64: $0.1) }
    }

    /// `~/Library/Caches/<bundle id ou VialetKit>/VialetKit/Fonts`, repli `$TMPDIR/VialetKit/Fonts`.
    static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent(Bundle.main.bundleIdentifier ?? "VialetKit", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VialetKit", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    /// Fichier d'une police : `<nom PostScript>-<octets>.ttf`.
    static func fileURL(name: String, byteCount: Int) -> URL {
        directory.appendingPathComponent("\(name)-\(byteCount).ttf")
    }

    private static func register(name: String, base64: String) -> Bool {
        if NSFont(name: name, size: 12) != nil { return true } // deja enregistree (ou installee)
        guard let data = Data(base64Encoded: base64), !data.isEmpty else {
            NSLog("VialetKit : police %@ illisible (base64)", name)
            return false
        }
        let url = fileURL(name: name, byteCount: data.count)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            if (attrs?[.size] as? NSNumber)?.intValue != data.count {
                try data.write(to: url, options: .atomic)
            }
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

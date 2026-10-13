import Foundation

/// Identite d'une app vialet.app, declaree une fois dans son Brand.swift :
/// nom, depot, bundle, palette et glyphe. Le reste (site, depot, cles, panneau
/// A propos, configuration de mise a jour) s'en deduit.
public struct AppIdentity: Sendable {
    /// Nom CamelCase ASCII (`Allege`) : prefixe des cles UserDefaults, sous-domaine du site.
    public let name: String
    /// Nom affiche, accents permis (Allege avec son accent grave).
    public let displayName: String
    /// Depot GitHub `proprietaire/nom` (`avialet/allege`).
    public let repository: String
    public let bundleIdentifier: String
    public let palette: AccentPalette
    /// Glyphe de la plaque (voir GlyphPath) ; vide pour l'initiale.
    public let glyph: String
    /// Trait du glyphe en `deep` plutot qu'en blanc sur la plaque.
    public let strokeDeep: Bool

    public init(name: String, displayName: String, repository: String, bundleIdentifier: String,
                palette: AccentPalette, glyph: String, strokeDeep: Bool = false) {
        self.name = name
        self.displayName = displayName
        self.repository = repository
        self.bundleIdentifier = bundleIdentifier
        self.palette = palette
        self.glyph = glyph
        self.strokeDeep = strokeDeep
    }

    /// `https://<name minuscule>.vialet.app`
    public var siteURL: URL { URL(string: "https://\(name.lowercased()).vialet.app")! }
    /// `https://github.com/<repository>`
    public var repositoryURL: URL { URL(string: "https://github.com/\(repository)")! }
    public var author: String { "Aur\u{00E9}lien Vialet" }
    public var license: String { "MIT" }

    /// Cle UserDefaults prefixee par le nom de l'app : `key("HotKey")` -> `AllegeHotKey`.
    public func key(_ suffix: String) -> String { name + suffix }
}

extension UpdaterConfiguration {
    public init(_ identity: AppIdentity) {
        self.init(repository: identity.repository, appName: identity.name,
                  bundleIdentifier: identity.bundleIdentifier, displayName: identity.displayName,
                  glyph: identity.glyph, strokeDeep: identity.strokeDeep)
    }
}

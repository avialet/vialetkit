import Foundation

/// Une app du menu de Vialet : ce qu'on sait d'elle installee, enrichi de sa fiche (HubManifest)
/// et du catalogue.
public struct HubEntry: Equatable, Sendable, Identifiable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let name: String
    public let displayName: String
    /// Version installee (Info.plist).
    public let version: String
    public let appURL: URL
    /// Schema valide (voir `HubSafety`) ; nil : pas d'URL d'action.
    public let scheme: String?
    /// Depot `avialet/<nom>` valide ; nil : pas de verification de mise a jour.
    public let repository: String?
    public let site: URL?
    /// Teintes de la fiche ; nil pour une app jamais lancee depuis Applications.
    public let palette: AccentPalette?
    public let glyph: String
    public let strokeDeep: Bool
    public let actions: [AppAction]
    /// Accroche du catalogue.
    public let tagline: String?
    /// Statut publie par l'app (fiche, deja borne par `HubManifest.decode`).
    public let status: String?
    /// Activite en cours (fiche) : choisit les actions `idle` ou `active`.
    public let active: Bool

    public init(bundleIdentifier: String, name: String, displayName: String, version: String, appURL: URL,
                scheme: String?, repository: String?, site: URL?, palette: AccentPalette?, glyph: String,
                strokeDeep: Bool, actions: [AppAction], tagline: String?, status: String? = nil, active: Bool = false) {
        self.bundleIdentifier = bundleIdentifier; self.name = name; self.displayName = displayName
        self.version = version; self.appURL = appURL; self.scheme = scheme; self.repository = repository
        self.site = site; self.palette = palette; self.glyph = glyph; self.strokeDeep = strokeDeep
        self.actions = actions; self.tagline = tagline; self.status = status; self.active = active
    }

    /// Les actions a proposer maintenant (`visible` selon `active`).
    public var visibleActions: [AppAction] { actions.filter { $0.visible.isShown(active: active) } }

    /// Sous le nom : le statut s'il y en a un, sinon l'accroche.
    public var subtitle: String? { status ?? tagline }

    /// `<scheme>://<id>` ; nil sans schema ou si l'identifiant est invalide.
    public func url(for actionID: String) -> URL? {
        guard actionID == "update" || AppAction.isValidIdentifier(actionID) else { return nil }
        return scheme.flatMap { AppAction.url(scheme: $0, id: actionID) }
    }

    /// `<scheme>://update` : l'app verifie et propose sa mise a jour.
    public var updateURL: URL? { url(for: "update") }
}

/// Contenu du menu : les apps installees, dans l'ordre du catalogue puis alphabetique, et les apps
/// du catalogue a decouvrir.
public struct HubListing: Equatable, Sendable {
    public let apps: [HubEntry]
    public let discover: [CatalogEntry]

    public init(apps: [HubEntry], discover: [CatalogEntry]) {
        self.apps = apps
        self.discover = discover
    }

    public static let empty = HubListing(apps: [], discover: [])

    /// Bundle de Vialet, jamais liste.
    public static let hubBundleIdentifier = "fr.vialet.vialet"

    public static func build(installed: [InstalledApp], manifests: [HubManifest], catalog: [CatalogEntry]?) -> HubListing {
        let byBundle = Dictionary(manifests.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let catalog = catalog ?? []
        func catalogIndex(_ app: InstalledApp) -> Int? {
            catalog.firstIndex { $0.bundleIdentifier == app.bundleIdentifier || $0.brand == app.name }
        }
        var seen = Set<String>()
        let apps = installed.filter { $0.bundleIdentifier != hubBundleIdentifier && seen.insert($0.bundleIdentifier).inserted }
        let sorted = apps.sorted { a, b in
            switch (catalogIndex(a), catalogIndex(b)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return a.displayName.compare(b.displayName, options: [.caseInsensitive, .diacriticInsensitive],
                                             locale: Locale(identifier: "fr_FR")) == .orderedAscending
            }
        }
        let entries = sorted.map { app -> HubEntry in
            let m = byBundle[app.bundleIdentifier]
            let listed = catalogIndex(app).map { catalog[$0] }
            // Schema : celui de l'Info.plist s'il y en a un, sinon celui de la fiche ; valide dans les deux cas.
            let scheme = (app.scheme?.lowercased() ?? m?.scheme).flatMap { HubSafety.isAcceptableScheme($0) ? $0 : nil }
            let fallback = "avialet/\(app.name.lowercased())"
            let repository = m.map(\.repository).flatMap { HubSafety.isValidRepository($0) ? $0 : nil }
                ?? (HubSafety.isValidRepository(fallback) ? fallback : nil)
            return HubEntry(bundleIdentifier: app.bundleIdentifier, name: app.name, displayName: app.displayName,
                            version: app.version, appURL: app.url, scheme: scheme,
                            repository: repository,
                            site: listed?.url ?? m.flatMap { URL(string: $0.site) }.flatMap { $0.scheme == "https" ? $0 : nil }
                                ?? URL(string: "https://\(app.name.lowercased()).vialet.app"),
                            palette: m?.accentPalette, glyph: m?.glyph ?? "", strokeDeep: m?.strokeDeep ?? false,
                            actions: m?.actions ?? [], tagline: listed.map(\.tagline).flatMap { $0.isEmpty ? nil : $0 },
                            status: m?.status, active: m?.active ?? false)
        }
        let discover = catalog.filter { entry in
            entry.isAvailable && entry.bundleIdentifier != hubBundleIdentifier
                && !apps.contains { $0.bundleIdentifier == entry.bundleIdentifier || $0.name == entry.brand }
        }
        return HubListing(apps: entries, discover: discover)
    }
}

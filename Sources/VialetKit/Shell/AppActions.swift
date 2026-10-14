import AppKit

/// Quand Vialet propose une action : toujours (defaut), au repos ou pendant une activite de l'app
/// (`HubManifest.active`, publie par `AppActions.publish(status:active:)`).
public enum AppActionVisibility: String, Codable, CaseIterable, Sendable {
    case always
    /// Seulement quand l'app n'est pas active (« 1 h » d'Eveil).
    case idle
    /// Seulement pendant une activite (« Arreter »).
    case active

    public func isShown(active: Bool) -> Bool {
        switch self {
        case .always: true
        case .idle: !active
        case .active: active
        }
    }
}

/// Action rapide d'une app, ouverte par l'URL `<nom>://<id>` (`pico://new`, `chuchote://dicter`)
/// et proposee par Vialet dans son menu.
public struct AppAction: Codable, Equatable, Sendable {
    /// Identifiant ASCII : minuscules, chiffres et tirets, 40 caracteres au plus, sans tiret initial.
    public let id: String
    /// Libelle francais (« Nouvelle tache »).
    public let title: String
    /// Symbole SF (`plus`, `mic`).
    public let symbol: String
    /// Raccourci de l'app tel qu'affiche (`⌘N`), pour information ; nil sans raccourci.
    public let shortcut: String?
    /// Quand Vialet la propose (`always` par defaut, non ecrit dans la fiche).
    public let visible: AppActionVisibility

    public init(_ id: String, title: String, symbol: String, shortcut: String? = nil,
                visible: AppActionVisibility = .always) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.visible = visible
    }

    private enum CodingKeys: String, CodingKey { case id, title, symbol, shortcut, visible }

    /// `visible` absent ou inconnu (ajout d'un kit plus recent) : `always`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        symbol = try c.decode(String.self, forKey: .symbol)
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut)
        visible = (try? c.decodeIfPresent(String.self, forKey: .visible)).flatMap { $0 }
            .flatMap(AppActionVisibility.init(rawValue:)) ?? .always
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(symbol, forKey: .symbol)
        try c.encodeIfPresent(shortcut, forKey: .shortcut)
        if visible != .always { try c.encode(visible, forKey: .visible) }
    }

    public static func isValidIdentifier(_ id: String) -> Bool {
        guard (1...40).contains(id.count), id.first != "-" else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    /// `<scheme>://<id>`
    public static func url(scheme: String, id: String) -> URL? {
        URL(string: "\(scheme)://\(id)")
    }
}

/// Ce que demande une URL `<nom>://...` adressee a l'app.
public enum AppURLCommand: Equatable, Sendable {
    /// `<nom>://` ou `<nom>://open` : montrer l'app.
    case open
    /// `<nom>://update` : verifier les mises a jour et montrer le resultat (lien « Mise a jour
    /// disponible » de Vialet).
    case checkForUpdates
    /// `<nom>://<id>` : une action declaree par l'app.
    case action(String)

    /// Identifiants reserves par le kit : une app ne peut pas les declarer comme actions.
    public static let reserved: Set<String> = ["open", "update"]

    /// nil si le schema n'est pas `scheme` (casse ignoree) ou si l'URL n'a pas la forme
    /// `<scheme>://<id>[/]` (ou `<scheme>:<id>`) avec un identifiant valide. La requete est ignoree.
    public static func parse(_ url: URL, scheme: String) -> AppURLCommand? {
        guard url.scheme?.lowercased() == scheme.lowercased() else { return nil }
        let host = url.host(percentEncoded: true) ?? ""
        let path = url.path(percentEncoded: true)
        let raw: String
        if host.isEmpty {
            raw = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            guard path.isEmpty || path == "/" else { return nil }
            raw = host
        }
        let id = raw.lowercased()
        if id.isEmpty || id == "open" { return .open }
        if id == "update" { return .checkForUpdates }
        return AppAction.isValidIdentifier(id) ? .action(id) : nil
    }
}

/// Actions rapides d'une app : leur registre, l'aiguillage des URL `<nom>://<id>` et leur
/// publication pour Vialet (voir `HubManifest`).
///
/// ```swift
/// let actions = AppActions(Brand.identity, open: { WindowSummoner.show() },
///                          checkForUpdates: { WindowSummoner.show(); Updater.shared.check() })
/// actions.register(AppAction("new", title: "Nouvelle tache", symbol: "plus", shortcut: "⌘N")) { ... }
/// actions.publish()                                    // au lancement
/// func application(_ app: NSApplication, open urls: [URL]) { actions.handle(urls) }
/// ```
@MainActor
public final class AppActions {
    public let identity: AppIdentity
    /// Schema d'URL de l'app (CFBundleURLSchemes de son Info.plist) : par defaut son nom en minuscules.
    public let scheme: String
    public private(set) var actions: [AppAction] = []
    /// Statut publie (`HubManifest.status`), garde d'une publication a l'autre.
    public private(set) var status: String?
    /// Activite en cours (`HubManifest.active`) : Vialet choisit les actions `idle` ou `active`.
    public private(set) var isActive = false
    /// L'app peut tenir le menu rassembleur (pose par `HubPresence.start`) : la fiche le dit (`hub`).
    public var hostsHub = false
    private var handlers: [String: @MainActor () -> Void] = [:]
    private let open: @MainActor () -> Void
    private let checkForUpdates: @MainActor () -> Void

    /// `open` montre l'app (et sert aux actions inconnues) ; `checkForUpdates` repond a
    /// `<nom>://update` (par defaut : `open`).
    public init(_ identity: AppIdentity, scheme: String? = nil, open: @escaping @MainActor () -> Void,
                checkForUpdates: (@MainActor () -> Void)? = nil) {
        self.identity = identity
        self.scheme = scheme ?? identity.name.lowercased()
        self.open = open
        self.checkForUpdates = checkForUpdates ?? open
    }

    /// Declare une action (dans l'ordre d'affichage) ; un meme identifiant remplace la precedente.
    /// Identifiant invalide ou reserve (`open`, `update`) : ignore, avec un message.
    public func register(_ action: AppAction, perform: @escaping @MainActor () -> Void) {
        guard AppAction.isValidIdentifier(action.id), !AppURLCommand.reserved.contains(action.id) else {
            NSLog("\(identity.displayName) action ignoree (identifiant invalide ou reserve) : \(action.id)")
            return
        }
        if let i = actions.firstIndex(where: { $0.id == action.id }) {
            actions[i] = action
        } else {
            actions.append(action)
        }
        handlers[action.id] = perform
    }

    /// Aiguille une URL de l'app ; false si elle ne lui est pas adressee. Action inconnue : `open`.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard let command = AppURLCommand.parse(url, scheme: scheme) else { return false }
        switch command {
        case .open: open()
        case .checkForUpdates: checkForUpdates()
        case .action(let id): (handlers[id] ?? open)()
        }
        return true
    }

    /// Pour `application(_:open:)`.
    public func handle(_ urls: [URL]) {
        for url in urls { handle(url) }
    }

    /// Le manifeste de l'app pour Vialet, tel que `publish()` l'ecrit.
    public func manifest(appURL: URL = Bundle.main.bundleURL, version: String = AppInfo.version) -> HubManifest {
        var m = HubManifest(identity: identity, version: version, appPath: appURL.path, scheme: scheme, actions: actions)
        m.status = status
        m.active = isActive
        m.hub = hostsHub ? HubElection.protocolVersion : nil
        return m
    }

    /// Change le statut affiche par Vialet sous le nom de l'app (60 caracteres au plus, une ligne ;
    /// nil : l'accroche) et l'activite (actions `idle` / `active`), puis republie la fiche. A appeler
    /// aux changements d'etat seulement (« Eveille jusqu'a 15 h 40 », pas un decompte).
    @discardableResult
    public func publish(status: String?, active: Bool, force: Bool = false,
                        directory: URL = HubManifest.directory) -> Bool {
        self.status = HubManifest.sanitizedStatus(status)
        isActive = active
        return publish(force: force, directory: directory)
    }

    /// Ecrit le manifeste dans `~/Library/Application Support/Vialet/apps/<bundle id>.json` et previent
    /// Vialet (`fr.vialet.apps.changed`). A appeler au lancement, apres `register`. Seulement pour une
    /// app rangee dans un dossier Applications (une version de developpement dans `build/` ne publie
    /// rien, sauf `force`). Renvoie true si le fichier a ete ecrit.
    @discardableResult
    public func publish(force: Bool = false, directory: URL = HubManifest.directory) -> Bool {
        let bundle = Bundle.main.bundleURL
        guard force || HubManifest.shouldPublish(bundleURL: bundle, home: FileManager.default.homeDirectoryForCurrentUser)
        else { return false }
        do {
            try manifest(appURL: bundle).write(to: directory)
            HubManifest.postAppsChanged()
            return true
        } catch {
            NSLog("\(identity.displayName) manifeste Vialet non ecrit : \(error)")
            return false
        }
    }
}

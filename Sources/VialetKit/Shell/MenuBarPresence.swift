import AppKit
import Observation
import SwiftUI

/// Choix de l'utilisateur pour l'icone de barre des menus d'une app.
public enum MenuBarMode: String, CaseIterable, Sendable {
    /// Masquee si l'app Vialet (qui rassemble les apps vialet.app) est installee, visible sinon.
    case auto
    case shown
    case hidden

    public var label: String {
        switch self {
        case .auto: "Automatique"
        case .shown: "Toujours"
        case .hidden: "Jamais"
        }
    }

    /// Mode range (`<App>MenuBarMode`), sinon migration de l'ancien booleen `<App>MenuBar` :
    /// false donne `hidden`, true ou absent `auto`. Une valeur inconnue compte comme absente.
    public static func resolve(stored: String?, legacyVisible: Bool?) -> MenuBarMode {
        if let stored, let mode = MenuBarMode(rawValue: stored) { return mode }
        return legacyVisible == false ? .hidden : .auto
    }

    public func isInserted(hubInstalled: Bool) -> Bool {
        switch self {
        case .auto: !hubInstalled
        case .shown: true
        case .hidden: false
        }
    }

    /// Avec l'election du menu rassembleur (`HubPresence`) : `auto` suit le role, `shown` et `hidden`
    /// restent le choix de l'utilisateur.
    public func isInserted(role: HubRole) -> Bool {
        switch self {
        case .auto: role.showsOwnIcon
        case .shown: true
        case .hidden: false
        }
    }

    /// Legende du reglage selon le role ; vide hors `auto`.
    public func status(role: HubRole, hubName: String) -> String {
        guard self == .auto else { return "" }
        switch role {
        case .vialet: return "Masqu\u{00E9}e : \(hubName) tourne et rassemble les apps."
        case .alone: return "Visible : c'est la seule app vialet.app de ce Mac."
        case .host, .member: return "Masqu\u{00E9}e : l'ic\u{00F4}ne vialet.app de la barre des menus rassemble les apps."
        }
    }

    /// Legende du reglage : ce que fait `auto` en ce moment ; vide pour les autres modes.
    public func status(hubInstalled: Bool, hubName: String) -> String {
        guard self == .auto else { return "" }
        return hubInstalled
            ? "Masqu\u{00E9}e : \(hubName) est install\u{00E9}e et rassemble les apps."
            : "Visible tant que \(hubName) n'est pas install\u{00E9}e."
    }
}

/// Presence de l'icone de barre des menus d'une app : `auto` (defaut) la masque quand l'app Vialet
/// est installee, `shown` et `hidden` la forcent. Re-evaluee a l'activation de l'app et a chaque
/// notification `fr.vialet.hub.changed` (envoyee par Vialet a son lancement et a sa fermeture).
///
/// ```swift
/// extension MenuBarPresence { static let shared = MenuBarPresence(app: Brand.identity) }
/// MenuBarExtra(isInserted: MenuBarPresence.shared.binding) { ... }
/// ```
@MainActor
@Observable
public final class MenuBarPresence {
    /// Bundle de l'app Vialet.
    public nonisolated static let hubBundleIdentifier = "fr.vialet.vialet"
    /// Notification distribuee par Vialet a son lancement et a sa fermeture.
    public nonisolated static let hubChangedNotification = Notification.Name("fr.vialet.hub.changed")

    public var mode: MenuBarMode {
        didSet { defaults.set(mode.rawValue, forKey: modeKey) }
    }
    /// Vialet installee (hors corbeille), au dernier `refresh()`.
    public private(set) var hubInstalled: Bool
    /// Role elu par `HubPresence` (nil sans election : `auto` suit seulement la presence de Vialet).
    /// Range sous `<App>HubRole` : au lancement suivant, le dernier role connu evite un clignotement.
    public internal(set) var hubRole: HubRole? {
        didSet { if persistsHubRole, let hubRole { defaults.set(hubRole.stored, forKey: roleKey) } }
    }
    /// Faux pour une app lancee hors d'un dossier Applications : son role n'est pas memorise.
    @ObservationIgnored var persistsHubRole = true

    /// Icone affichee. Le systeme y ecrit false quand l'utilisateur retire l'icone de la barre
    /// (Cmd-glisser) : le mode passe alors a `hidden` (et a `shown` dans l'autre sens).
    public var isInserted: Bool {
        get { hubRole.map { mode.isInserted(role: $0) } ?? mode.isInserted(hubInstalled: hubInstalled) }
        set {
            guard newValue != isInserted else { return }
            mode = newValue ? .shown : .hidden
        }
    }

    /// `$isInserted` pour `MenuBarExtra(isInserted:)`.
    public var binding: Binding<Bool> {
        Binding(get: { self.isInserted }, set: { self.isInserted = $0 })
    }

    private let defaults: UserDefaults
    private let modeKey: String
    private let roleKey: String
    private let hubLocator: @MainActor () -> Bool
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public convenience init(app: AppIdentity) {
        self.init(app: app, defaults: .standard, hubLocator: { MenuBarPresence.locateHub() }, observe: true)
    }

    init(app: AppIdentity, defaults: UserDefaults, hubLocator: @escaping @MainActor () -> Bool, observe: Bool) {
        self.defaults = defaults
        self.modeKey = app.key("MenuBarMode")
        self.roleKey = app.key("HubRole")
        self.hubRole = HubRole(stored: defaults.string(forKey: app.key("HubRole")))
        self.hubLocator = hubLocator
        let legacy = defaults.object(forKey: app.key("MenuBar")) as? Bool
        let mode = MenuBarMode.resolve(stored: defaults.string(forKey: modeKey), legacyVisible: legacy)
        self.mode = mode
        self.hubInstalled = hubLocator()
        defaults.set(mode.rawValue, forKey: modeKey)
        if observe { startObserving() }
    }

    /// Legende du reglage (vide hors `auto`).
    public var status: String {
        hubRole.map { mode.status(role: $0, hubName: "Vialet") } ?? mode.status(hubInstalled: hubInstalled, hubName: "Vialet")
    }

    /// Relit la presence de Vialet.
    public func refresh() {
        let installed = hubLocator()
        if installed != hubInstalled { hubInstalled = installed }
    }

    private func startObserving() {
        let local = NotificationCenter.default
        let distributed = DistributedNotificationCenter.default()
        let onActive = local.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let onHub = distributed.addObserver(forName: Self.hubChangedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers = [(local, onActive), (distributed, onHub)]
    }

    // MARK: Vialet

    /// Emplacement de Vialet retenu : un bundle hors de la corbeille.
    nonisolated static func isUsableHubLocation(_ url: URL?) -> Bool {
        guard let url else { return false }
        return !url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// Vialet est-elle installee (LaunchServices, hors corbeille) ?
    public static func locateHub() -> Bool {
        isUsableHubLocation(NSWorkspace.shared.urlForApplication(withBundleIdentifier: hubBundleIdentifier))
    }

    /// Envoye par Vialet a son lancement et a sa fermeture : les apps re-evaluent leur icone.
    public static func postHubChanged() {
        DistributedNotificationCenter.default().postNotificationName(hubChangedNotification, object: nil,
                                                                    userInfo: nil, deliverImmediately: true)
    }
}

import AppKit

/// Faits d'une election, relus a chaque changement (lancement ou fin d'une app vialet.app, fiche
/// publiee, Vialet installee ou quittee).
public struct HubFacts: Equatable, Sendable {
    public var me: String
    /// Apps vialet.app retenues comme installees (dossiers Applications et fiches validees).
    public var installed: Set<String>
    /// Parmi elles, celles qui peuvent heberger (fiche avec `hub`).
    public var capable: Set<String>
    /// Bundle ids des apps vialet.app en cours, lancees depuis un dossier Applications (`HubElection.running`).
    public var running: Set<String>

    public init(me: String, installed: Set<String>, capable: Set<String>, running: Set<String>) {
        self.me = me; self.installed = installed; self.capable = capable; self.running = running
    }

    /// L'app Vialet tourne (installee mais arretee, elle ne rassemble rien).
    public var hubAppRunning: Bool { running.contains(MenuBarPresence.hubBundleIdentifier) }

    public var role: HubRole {
        HubElection.role(me: me, hubAppRunning: hubAppRunning, installed: installed,
                         runningHosts: capable.intersection(running))
    }
}

/// Ce que fait l'app quand elle devient hote ou cesse de l'etre (icone vialet.app et son modele).
@MainActor
protocol HubHosting: AnyObject {
    func show()
    func hide()
}

/// Icone et modele reels du menu rassembleur.
@MainActor
final class HubStatusHosting: HubHosting {
    let item: HubStatusItem
    init(item: HubStatusItem) { self.item = item }
    func show() { item.model.start(); item.install() }
    func hide() { item.remove(); item.model.stop() }
}

/// Le menu rassembleur sans l'app Vialet. Une app vialet.app (kit 0.2.6 ou plus) qui l'adopte :
/// - garde son icone si elle est la seule app vialet.app installee ;
/// - des qu'il y en a deux, une seule des apps en cours (le plus petit bundle id parmi celles qui
///   l'ont adopte) affiche l'icone vialet.app et le menu de toutes les apps ; les autres masquent
///   leur icone (mode `auto` de `MenuBarPresence` ; `shown` et `hidden` restent respectes) ;
/// - si l'app Vialet est installee, c'est elle qui rassemble.
/// L'election est refaite au lancement et a la fin de chaque app vialet.app (delai court, sans
/// clignotement) ; une app au kit plus ancien ne la connait pas et garde son icone.
///
/// ```swift
/// // applicationDidFinishLaunching, apres AppActions.shared.register(...) (publie la fiche) :
/// HubPresence.start(menuBar: .shared, actions: .shared, updater: .shared)
/// ```
@MainActor
public final class HubPresence {
    /// L'instance demarree par `start`.
    public private(set) static var current: HubPresence?

    public let menuBar: MenuBarPresence
    public let actions: AppActions
    /// Role courant (le dernier connu au lancement).
    public private(set) var role: HubRole
    /// Le menu tenu par cette app quand elle est hote.
    public let statusItem: HubStatusItem?

    private let hosting: HubHosting
    private let announce: @MainActor () -> Void
    private var hostingShown = false
    private var generation = 0
    private var pending: DispatchWorkItem?
    /// Apps qui ont quitte pendant l'attente de la prochaine election.
    private var pendingEnded: Set<String> = []
    private var lastScan: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Delai avant une election (coalesce les notifications, laisse finir une app qui quitte).
    public nonisolated static let delay: TimeInterval = 0.4
    /// Delai de la premiere election, au lancement.
    public nonisolated static let firstDelay: TimeInterval = 1

    /// Demarre l'election : la fiche porte desormais `hub` (republiee), le dernier role connu est
    /// applique tout de suite, puis l'election est refaite. Un second appel rend l'instance existante.
    /// Hors d'un dossier Applications (image disque, Telechargements, translocation), l'app garde son
    /// icone : ni election, ni menu rassembleur.
    @discardableResult
    public static func start(menuBar: MenuBarPresence, actions: AppActions, updater: Updater) -> HubPresence {
        if let current { return current }
        let model = HubModel(identity: actions.identity, updater: updater)
        let item = HubStatusItem(model: model, options: HubMenuOptions(),
                                 toolTip: "vialet.app, menu tenu par \(actions.identity.displayName)",
                                 autosaveName: "VialetHub")
        let presence = HubPresence(menuBar: menuBar, actions: actions, hosting: HubStatusHosting(item: item),
                                   statusItem: item, announce: { HubPresence.postHostChanged() })
        current = presence
        let home = FileManager.default.homeDirectoryForCurrentUser
        presence.begin(inApplications: HubManifest.shouldPublish(bundleURL: Bundle.main.bundleURL, home: home))
        return presence
    }

    init(menuBar: MenuBarPresence, actions: AppActions, hosting: HubHosting, statusItem: HubStatusItem?,
         announce: @escaping @MainActor () -> Void) {
        self.menuBar = menuBar
        self.actions = actions
        self.hosting = hosting
        self.statusItem = statusItem
        self.announce = announce
        self.role = menuBar.hubRole ?? .alone
    }

    func begin(inApplications: Bool) {
        guard inApplications else {
            menuBar.persistsHubRole = false
            apply(.alone, announcing: false)
            return
        }
        actions.hostsHub = true
        actions.publish()
        // Dernier role connu, sauf un hote memorise alors qu'un autre tient deja le menu.
        let running = Self.runningApps(ended: [])
        let capable = HubElection.capable(manifests: HubManifest.loadAll(from: HubManifest.directory), installed: running)
        let initial = HubElection.initialRole(stored: menuBar.hubRole, me: actions.identity.bundleIdentifier,
                                              hubAppRunning: running.contains(MenuBarPresence.hubBundleIdentifier),
                                              runningHosts: capable)
        apply(initial, announcing: false)
        observe()
        refresh(delay: Self.firstDelay)
    }

    /// Applique un role : icone propre (via `MenuBarPresence`), icone et menu vialet.app, annonce aux
    /// autres apps quand cette app prend ou quitte le role d'hote.
    func apply(_ role: HubRole, announcing: Bool = true) {
        let wasHosting = hostingShown
        self.role = role
        if menuBar.hubRole != role { menuBar.hubRole = role }
        if role.hostsHub, !hostingShown {
            hosting.show()
            hostingShown = true
        } else if !role.hostsHub, hostingShown {
            hosting.hide()
            hostingShown = false
        }
        if announcing, wasHosting != hostingShown { announce() }
    }

    /// Refait l'election apres `delay`, et au moins `HubElection.minScanInterval` apres la precedente (les
    /// demandes rapprochees n'en font qu'une). `ended` : bundle id d'une app qui vient de quitter, ecarte
    /// meme si le systeme la liste encore (cumule jusqu'a l'election).
    public func refresh(delay: TimeInterval = HubPresence.delay, ended: String? = nil) {
        if let ended { pendingEnded.insert(ended) }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.elect() }
        }
        pending = work
        let wait = HubElection.scanDelay(requested: delay, now: Date(), lastScan: lastScan)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// Apps `fr.vialet.*` en cours depuis un dossier Applications.
    static func runningApps(ended: Set<String>) -> Set<String> {
        let processes = NSWorkspace.shared.runningApplications.map {
            HubProcess(bundleIdentifier: $0.bundleIdentifier, bundleURL: $0.bundleURL, isTerminated: $0.isTerminated)
        }
        let roots = HubManifest.applicationRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        return HubElection.running(processes, roots: roots, ended: ended)
    }

    private func elect() {
        generation += 1
        lastScan = Date()
        let ticket = generation
        let ended = pendingEnded
        pendingEnded = []
        let me = actions.identity.bundleIdentifier
        Task.detached(priority: .utility) {
            let found = HubScan.installed(catalog: nil)
            let installed = Set(found.apps.map(\.bundleIdentifier))
            let capable = HubElection.capable(manifests: found.manifests, installed: installed)
            await MainActor.run { [weak self] in
                guard let self, ticket == self.generation else { return }
                let facts = HubFacts(me: me, installed: installed, capable: capable,
                                     running: Self.runningApps(ended: ended))
                self.apply(facts.role)
            }
        }
    }

    private func observe() {
        let distributed = DistributedNotificationCenter.default()
        for name in [MenuBarPresence.hubChangedNotification, HubManifest.appsChangedNotification, HubElection.hostNotification] {
            let token = distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((distributed, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let terminated = name == NSWorkspace.didTerminateApplicationNotification
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, id.hasPrefix(InstalledApp.bundlePrefix) else { return }
                MainActor.assumeIsolated { self?.refresh(ended: terminated ? id : nil) }
            }
            observers.append((workspace, token))
        }
        let local = NotificationCenter.default
        let quit = local.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // Les autres apps refont l'election sans attendre la fin du processus.
            MainActor.assumeIsolated { HubPresence.postHostChanged() }
        }
        observers.append((local, quit))
    }

    /// `fr.vialet.hub.host` : les apps vialet.app refont l'election.
    public static func postHostChanged() {
        DistributedNotificationCenter.default().postNotificationName(HubElection.hostNotification, object: nil,
                                                                    userInfo: nil, deliverImmediately: true)
    }
}

import AppKit
import Observation

/// Lecture des apps vialet.app du Mac, commune au menu et a l'election : apps des dossiers
/// Applications, fiches (non fiables, validees) et LaunchServices pour le catalogue.
public enum HubScan {
    /// Apps installees retenues et fiches lues. Racines `/Applications` et `~/Applications` ; un `.app` ou
    /// un dossier en lien qui en sort est ecarte ; une app d'un sous-dossier plus profond (fiche,
    /// LaunchServices) n'est retenue que dans les racines et si son Info.plist porte le bundle attendu.
    public static func installed(catalog: [CatalogEntry]?,
                                 home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                 manifestsDirectory: URL = HubManifest.directory) -> (apps: [InstalledApp], manifests: [HubManifest]) {
        let roots = HubManifest.applicationRoots(home: home)
        var installed = InstalledApp.scan(directories: roots) { HubSafety.isAcceptableAppURL($0, roots: roots) }
        let manifests = HubManifest.loadAll(from: manifestsDirectory)
        func add(_ url: URL?, expecting bundleIdentifier: String) {
            guard let url, HubSafety.isAcceptableAppURL(url, roots: roots),
                  let app = InstalledApp.read(bundleURL: url), app.bundleIdentifier == bundleIdentifier,
                  !installed.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
            installed.append(app)
        }
        // Fiches (non fiables) : chemin d'app dans un dossier Applications seulement.
        for m in manifests where HubSafety.isAcceptableAppPath(m.appPath, roots: roots) {
            add(URL(fileURLWithPath: m.appPath), expecting: m.bundleIdentifier)
        }
        // Catalogue : LaunchServices.
        for entry in catalog ?? [] {
            add(NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier),
                expecting: entry.bundleIdentifier)
        }
        return (installed, manifests)
    }

    public static func listing(catalog: [CatalogEntry]?) -> HubListing {
        let found = installed(catalog: catalog)
        return HubListing.build(installed: found.apps, manifests: found.manifests, catalog: catalog)
    }
}

/// Ce que montre le menu rassembleur : les apps installees (fiches publiees, Info.plist, catalogue),
/// leurs mises a jour en attente, et les apps du catalogue a decouvrir. Tenu par l'app Vialet, ou par
/// l'app elue hote (`HubPresence`) quand Vialet n'est pas installee.
///
/// Reseau, seulement si la recherche automatique de l'app est active : le catalogue vialet.app une fois
/// par jour, la derniere Release GitHub de chaque app au lancement puis toutes les 6 h (plancher 30 min,
/// requetes conditionnelles ETag, arret sur quota). Reponses bornees a 2 Mo.
@MainActor
@Observable
public final class HubModel {
    public private(set) var listing: HubListing = .empty
    /// Version publiee plus recente que l'installee, par bundle id.
    public private(set) var updates: [String: SemanticVersion] = [:]

    /// L'app qui tient le menu (cles UserDefaults, User-Agent) et son verificateur (recherche automatique).
    public let identity: AppIdentity
    public let updater: Updater
    /// Sa propre mise a jour compte pour le point de l'icone (Vialet, qui ne se liste pas).
    public let announcesOwnUpdate: Bool

    @ObservationIgnored private var plateCache: [String: NSImage] = [:]
    @ObservationIgnored private var isPreview = false
    @ObservationIgnored private var catalog: [CatalogEntry]?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var firstCheckTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var isCheckingApps = false

    private let defaults = UserDefaults.standard
    private var lastAppsCheckKey: String { identity.key("LastAppsCheck") }
    private var catalogFetchedKey: String { identity.key("CatalogFetched") }
    /// Mises a jour trouvees, gardees d'un lancement a l'autre (le plancher de 30 min s'applique aussi
    /// apres une relance).
    private var updatesKey: String { identity.key("AppUpdates") }
    /// ETag de la derniere Release lue, par depot (requetes conditionnelles).
    private var etagsKey: String { identity.key("ReleaseETags") }
    /// Une verification a deja abouti : le resultat garde (aucune mise a jour) vaut pour un 304.
    private var lastAppsCheckKnown: Bool { defaults.object(forKey: lastAppsCheckKey) != nil }

    public init(identity: AppIdentity, updater: Updater, announcesOwnUpdate: Bool = false) {
        self.identity = identity
        self.updater = updater
        self.announcesOwnUpdate = announcesOwnUpdate
    }

    /// Cles UserDefaults de ce modele (pour un test de compatibilite).
    public var defaultsKeys: [String] { [lastAppsCheckKey, catalogFetchedKey, updatesKey, etagsKey] }

    /// Mises a jour a signaler pour les apps listees (une app deja a jour n'apparait plus).
    public var pendingUpdates: [HubEntry] {
        listing.apps.filter { entry in
            guard let next = updates[entry.bundleIdentifier] else { return false }
            return SemanticVersion(string: entry.version).map { next > $0 } ?? false
        }
    }

    /// Point de la barre des menus : une app (ou l'app hote elle-meme) attend une mise a jour.
    public var hasPendingUpdate: Bool { !pendingUpdates.isEmpty || (announcesOwnUpdate && updater.announced != nil) }

    private static var supportDirectory: URL { HubManifest.directory.deletingLastPathComponent() }
    private static var catalogCacheURL: URL { supportDirectory.appendingPathComponent("catalog.json") }

    // MARK: Chargement

    /// Catalogue en cache, liste, puis (si la recherche automatique est permise) catalogue du jour et
    /// mises a jour des apps apres 6 s, toutes les 6 h ensuite. Sans effet si deja demarre.
    public func start() {
        guard periodicTask == nil, !isPreview else { return }
        catalog = Catalog.load(from: Self.catalogCacheURL)
        let saved = defaults.dictionary(forKey: updatesKey) as? [String: String] ?? [:]
        updates = saved.compactMapValues(SemanticVersion.init(string:))
        reload()
        observe()
        firstCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.refreshCatalogIfNeeded()
            self?.checkAppsIfNeeded()
        }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HubUpdates.interval))
                guard !Task.isCancelled else { return }
                self?.checkAppsIfNeeded()
                self?.refreshCatalogIfNeeded()
            }
        }
    }

    /// Arrete observations et verifications (l'app n'est plus hote).
    public func stop() {
        periodicTask?.cancel(); periodicTask = nil
        firstCheckTask?.cancel(); firstCheckTask = nil
        reloadTask?.cancel(); reloadTask = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }

    /// Relit les apps installees et leurs fiches (hors du fil principal).
    public func reload() {
        guard !isPreview else { return }
        let catalog = self.catalog
        reloadTask?.cancel()
        reloadTask = Task.detached(priority: .utility) { [weak self] in
            let listing = HubScan.listing(catalog: catalog)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                if listing != self.listing {
                    self.listing = listing
                    self.plateCache = [:]
                }
            }
        }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let onApps = distributed.addObserver(forName: HubManifest.appsChangedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        observers.append((distributed, onApps))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier?.hasPrefix(InstalledApp.bundlePrefix) == true else { return }
                MainActor.assumeIsolated { self?.reload() }
            }
            observers.append((workspace, token))
        }
    }

    // MARK: Catalogue

    private func refreshCatalogIfNeeded() {
        guard !isPreview, updater.autoCheck,
              Catalog.shouldRefresh(now: Date(), lastFetch: defaults.object(forKey: catalogFetchedKey) as? Date)
        else { return }
        Task {
            var request = URLRequest(url: Catalog.url)
            request.timeoutInterval = 15
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  HubSafety.isAcceptableResponse(byteCount: data.count, expectedLength: response.expectedContentLength),
                  let entries = Catalog.parse(data) else { return }
            try? FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            try? data.write(to: Self.catalogCacheURL, options: .atomic)
            defaults.set(Date(), forKey: catalogFetchedKey)
            catalog = entries
            reload()
        }
    }

    // MARK: Mises a jour

    /// Derniere Release de chaque app listee, si la recherche automatique est permise et que la
    /// derniere verification date d'au moins 30 min.
    public func checkAppsIfNeeded() {
        guard !isPreview, updater.autoCheck,
              HubUpdates.shouldCheck(now: Date(), lastCheck: defaults.object(forKey: lastAppsCheckKey) as? Date)
        else { return }
        checkApps()
    }

    public func checkApps() {
        let apps = listing.apps
        guard !apps.isEmpty, !isCheckingApps else { return }
        isCheckingApps = true
        let agent = identity.name
        Task {
            defer { isCheckingApps = false }
            var found: [String: SemanticVersion] = [:]
            var checked = Set<String>()
            var stopped = false
            var etags = defaults.dictionary(forKey: etagsKey) as? [String: String] ?? [:]
            for app in apps {
                guard let repository = app.repository, let url = HubUpdates.releaseURL(repository: repository) else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue(agent, forHTTPHeaderField: "User-Agent")
                // ETag : une Release inchangee repond 304, sans compter dans le quota de GitHub.
                if let etag = etags[repository], updates[app.bundleIdentifier] != nil || lastAppsCheckKnown {
                    request.setValue(etag, forHTTPHeaderField: "If-None-Match")
                }
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let http = response as? HTTPURLResponse,
                      HubSafety.isAcceptableResponse(byteCount: data.count, expectedLength: http.expectedContentLength)
                else { continue }
                switch HubUpdates.outcome(status: http.statusCode) {
                case .result:
                    checked.insert(app.bundleIdentifier)
                    etags[repository] = http.value(forHTTPHeaderField: "ETag")
                    if http.statusCode == 200,
                       let next = HubUpdates.available(installed: app.version, releaseJSON: data, appName: app.name) {
                        found[app.bundleIdentifier] = next
                    }
                case .unchanged:
                    checked.insert(app.bundleIdentifier)
                    if let previous = updates[app.bundleIdentifier] { found[app.bundleIdentifier] = previous }
                case .stop:
                    stopped = true
                case .skip:
                    break
                }
                if stopped { break }
            }
            defaults.set(etags, forKey: etagsKey)
            let merged = HubUpdates.merge(previous: updates, found: found, checked: checked)
            defaults.set(merged.mapValues(\.description), forKey: updatesKey)
            updates = merged
            // Horodatage seulement pour une verification complete : coupee par le quota, on reessaiera.
            if !stopped, !checked.isEmpty { defaults.set(Date(), forKey: lastAppsCheckKey) }
        }
    }

    // MARK: Actions

    /// Le bundle de l'entree, relu juste avant de l'ouvrir : un `.app` dans /Applications ou
    /// ~/Applications (liens symboliques resolus) dont l'Info.plist porte toujours le bundle attendu ;
    /// nil sinon (rien n'est ouvert).
    private func verifiedAppURL(_ entry: HubEntry) -> URL? {
        let url = entry.appURL
        let roots = HubManifest.applicationRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        guard HubSafety.isAcceptableAppURL(url, roots: roots),
              InstalledApp.read(bundleURL: url)?.bundleIdentifier == entry.bundleIdentifier else {
            reload()
            return nil
        }
        return url
    }

    public func open(_ entry: HubEntry) {
        guard let app = verifiedAppURL(entry) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// `<scheme>://<id>` adresse a cette app precisement (pas a une autre copie). L'app est activee
    /// (fenetre, feuille ou editeur au premier plan avec le clavier), sauf pour les actions qui
    /// travaillent pour l'app deja au premier plan : une dictee doit se coller la ou l'on etait.
    public func perform(_ action: AppAction, of entry: HubEntry) {
        guard let url = entry.url(for: action.id) else { return open(entry) }
        guard let app = verifiedAppURL(entry) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = Self.activates(bundleIdentifier: entry.bundleIdentifier, action: action.id)
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }

    /// Actions qui ne doivent pas faire passer leur app au premier plan.
    public nonisolated static let backgroundActions: Set<String> = ["fr.vialet.chuchote/dicter"]

    public nonisolated static func activates(bundleIdentifier: String, action: String) -> Bool {
        !backgroundActions.contains("\(bundleIdentifier)/\(action)")
    }

    /// L'app verifie et propose sa mise a jour (`<scheme>://update`) ; sans schema, elle s'ouvre
    /// (sa verification de lancement s'en charge).
    public func update(_ entry: HubEntry) {
        guard let url = entry.updateURL else { return open(entry) }
        guard let app = verifiedAppURL(entry) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    public func openSite(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }

    /// Plaque de l'app (fiche : plaque plate du kit ; sinon icone du bundle).
    public func plate(for entry: HubEntry) -> NSImage {
        if let cached = plateCache[entry.bundleIdentifier] { return cached }
        let image: NSImage
        if let palette = entry.palette {
            image = GlyphImage.plate(palette, glyph: entry.glyph, pixels: 64, strokeDeep: entry.strokeDeep)
        } else {
            image = NSWorkspace.shared.icon(forFile: entry.appURL.path)
        }
        plateCache[entry.bundleIdentifier] = image
        return image
    }

    /// Teintes des apps listees, pour la plaque du hub en tete du menu.
    public var palettes: [AccentPalette] { listing.apps.compactMap(\.palette) }

    // MARK: Apercu

    #if DEBUG
    /// Mode capture (DEBUG) : liste et mises a jour fictives, sans reseau ni fichier.
    public func preview(_ listing: HubListing, updates: [String: SemanticVersion], plates: [String: NSImage] = [:]) {
        isPreview = true
        self.listing = listing
        self.updates = updates
        plateCache = plates
    }
    #endif
}

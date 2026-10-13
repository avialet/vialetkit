import AppKit
import CryptoKit
import Observation

/// Ce que l'updater doit savoir d'une app. `appName` est l'identifiant ASCII
/// (nom du DMG `<appName>-X.Y.Z.dmg`, du bundle `<appName>.app`) ; `displayName`
/// sert aux messages.
public struct UpdaterConfiguration: Sendable {
    public let repository: String
    public let appName: String
    public let displayName: String
    public let bundleIdentifier: String
    public let defaultsPrefix: String
    /// Glyphe de l'app (AppIdentity.glyph) pour l'icone de `UpdateNotice` ; vide : symbole.
    public let glyph: String
    /// Trait du glyphe en `deep` plutot qu'en blanc sur la plaque.
    public let strokeDeep: Bool

    public init(repository: String, appName: String, bundleIdentifier: String,
                displayName: String? = nil, defaultsPrefix: String? = nil,
                glyph: String = "", strokeDeep: Bool = false) {
        self.repository = repository
        self.appName = appName
        self.displayName = displayName ?? appName
        self.bundleIdentifier = bundleIdentifier
        self.defaultsPrefix = defaultsPrefix ?? appName
        self.glyph = glyph
        self.strokeDeep = strokeDeep
    }

    public var releaseURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }
    /// `releases/tags/v<version>` : notes de la version installee, apres une mise a jour.
    func releaseURL(tag version: SemanticVersion) -> URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/tags/v\(version)")!
    }
    var autoKey: String { defaultsPrefix + "AutoUpdate" }
    var lastCheckKey: String { defaultsPrefix + "LastUpdateCheck" }
    /// Version ecartee par << Plus tard >> dans `UpdateNotice`.
    var dismissedKey: String { defaultsPrefix + "DismissedUpdate" }
    /// Derniere version dont les nouveautes ont ete vues.
    var lastSeenKey: String { defaultsPrefix + "LastSeenVersion" }
}

public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(Double)
    case verifying
    case installing
    case failed(String)
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Mises a jour a la volee : lit la derniere Release GitHub, telecharge le DMG,
/// verifie son empreinte SHA-256, controle l'app qu'il contient, puis la
/// remplace et relance l'app. Rien n'est modifie tant qu'une etape echoue.
@MainActor
@Observable
public final class Updater {
    public let configuration: UpdaterConfiguration
    public private(set) var state: UpdateState = .idle
    public private(set) var lastCheck: Date?
    public var autoCheck: Bool {
        didSet { defaults?.set(autoCheck, forKey: configuration.autoKey) }
    }

    public let currentVersion: SemanticVersion
    /// Version ecartee par << Plus tard >> : elle n'est plus annoncee, la suivante si.
    public private(set) var dismissedVersion: SemanticVersion?
    /// Version installee dont les nouveautes n'ont pas encore ete vues (premier lancement apres
    /// une mise a jour) ; nil sinon. `acknowledgeUpdate()` la marque comme vue.
    public private(set) var updatedVersion: SemanticVersion?
    /// Nouveautes de `updatedVersion`, lues dans sa Release (nil tant qu'elles ne sont pas connues).
    public private(set) var updatedNotes: ReleaseNotes?
    /// Release dont l'installation a echoue (pour reessayer depuis le bandeau).
    private(set) var failedRelease: ReleaseInfo?

    /// nil : aucune persistance (apercus du mode capture).
    private let defaults: UserDefaults?
    private var task: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var notesTask: Task<Void, Never>?
    /// Lecture de la derniere Release en cours (verification manuelle ou silencieuse).
    private var isFetching = false
    private var fetchIsUserInitiated = false

    public convenience init(configuration: UpdaterConfiguration) {
        self.init(configuration: configuration, defaults: .standard, currentVersion: AppInfo.semanticVersion)
    }

    init(configuration: UpdaterConfiguration, defaults: UserDefaults?, currentVersion: SemanticVersion) {
        self.configuration = configuration
        self.defaults = defaults
        self.currentVersion = currentVersion
        autoCheck = defaults?.object(forKey: configuration.autoKey) as? Bool ?? true
        lastCheck = defaults?.object(forKey: configuration.lastCheckKey) as? Date
        dismissedVersion = defaults?.string(forKey: configuration.dismissedKey).flatMap(SemanticVersion.init(string:))
        guard let defaults else { return }
        let lastSeen = defaults.string(forKey: configuration.lastSeenKey).flatMap(SemanticVersion.init(string:))
        if Self.justUpdated(current: currentVersion, lastSeen: lastSeen, hasRunBefore: lastCheck != nil) {
            updatedVersion = currentVersion
        } else if currentVersion > SemanticVersion(0), lastSeen != currentVersion {
            defaults.set(currentVersion.description, forKey: configuration.lastSeenKey)
        }
    }

    public var available: ReleaseInfo? {
        if case .available(let r) = state { return r }
        return nil
    }

    /// La version disponible, si elle n'a pas ete ecartee par << Plus tard >> : ce qu'annonce `UpdateNotice`.
    public var announced: ReleaseInfo? {
        guard let release = available, Self.shouldAnnounce(release.version, dismissed: dismissedVersion) else { return nil }
        return release
    }

    nonisolated static func shouldAnnounce(_ version: SemanticVersion, dismissed: SemanticVersion?) -> Bool {
        dismissed.map { version > $0 } ?? true
    }

    /// Premier lancement apres une mise a jour : version connue plus recente que la derniere vue ;
    /// sans version vue (cle anterieure a VialetKit 0.2.2), l'app a deja tourne si elle a deja
    /// verifie les mises a jour.
    nonisolated static func justUpdated(current: SemanticVersion, lastSeen: SemanticVersion?, hasRunBefore: Bool) -> Bool {
        guard current > SemanticVersion(0) else { return false }
        if let lastSeen { return current > lastSeen }
        return hasRunBefore
    }

    /// << Plus tard >> : n'annonce plus cette version (la carte des Reglages la propose toujours).
    public func dismissAvailable() {
        guard let release = available ?? failedRelease else { return }
        dismissedVersion = release.version
        defaults?.set(release.version.description, forKey: configuration.dismissedKey)
        if case .failed = state, failedRelease != nil {
            state = .available(release)
            failedRelease = nil
        }
    }

    /// Apercu (mode capture) : montre les nouveautes de `version` comme apres une mise a jour.
    func previewUpdated(_ version: SemanticVersion, notes: ReleaseNotes?) {
        updatedVersion = version
        updatedNotes = notes
    }

    /// << OK >> du bandeau << a ete mis a jour >> : les nouveautes de cette version sont vues.
    public func acknowledgeUpdate() {
        updatedVersion = nil
        updatedNotes = nil
        defaults?.set(currentVersion.description, forKey: configuration.lastSeenKey)
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .verifying, .installing: true
        default: false
        }
    }

    // MARK: Verification de version

    /// Intervalle des verifications automatiques tant que l'app tourne (6 h).
    nonisolated static let automaticInterval: TimeInterval = 6 * 3600
    /// Plancher entre deux verifications automatiques (30 min), pour le quota de l'API GitHub.
    nonisolated static let automaticFloor: TimeInterval = 30 * 60

    /// Decision d'une verification automatique : jamais si l'utilisateur l'a coupee, sinon des
    /// qu'au moins 30 min separent `now` de la derniere verification reussie (ou qu'il n'y en a pas,
    /// ou que l'horloge a recule).
    nonisolated static func shouldCheckAutomatically(now: Date, lastCheck: Date?, autoCheck: Bool) -> Bool {
        guard autoCheck else { return false }
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= automaticFloor
    }

    /// A chaque lancement (l'app l'appelle quelques secondes apres l'ouverture), puis toutes les 6 h
    /// tant que l'app tourne, avec un plancher de 30 min entre deux verifications et si
    /// l'utilisateur l'accepte. Une verification automatique est silencieuse : l'etat ne passe
    /// pas par `.checking` et un echec reseau ne change rien.
    public func checkAutomatically() {
        startPeriodicChecks()
        fetchUpdatedNotesIfNeeded()
        guard Self.shouldCheckAutomatically(now: Date(), lastCheck: lastCheck, autoCheck: autoCheck) else { return }
        check(userInitiated: false)
    }

    private func startPeriodicChecks() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.automaticInterval))
                guard let self else { return }
                if Self.shouldCheckAutomatically(now: Date(), lastCheck: lastCheck, autoCheck: autoCheck) {
                    check(userInitiated: false)
                }
            }
        }
    }

    public func check(userInitiated: Bool = true) {
        if isFetching {
            // Une demande de l'utilisateur pendant une verification silencieuse la rend visible.
            if userInitiated, !fetchIsUserInitiated, !isBusy { fetchIsUserInitiated = true; state = .checking }
            return
        }
        guard !isBusy else { return }
        isFetching = true
        fetchIsUserInitiated = userInitiated
        if userInitiated { state = .checking; failedRelease = nil }
        let configuration = configuration
        task = Task { [weak self] in
            guard let self else { return }
            defer { isFetching = false }
            do {
                let release = try await Self.fetchLatest(configuration)
                lastCheck = Date()
                UserDefaults.standard.set(lastCheck, forKey: configuration.lastCheckKey)
                // Une verification silencieuse ne remplace pas une installation lancee entre-temps.
                guard fetchIsUserInitiated || !isBusy else { return }
                apply(latest: release)
            } catch {
                if fetchIsUserInitiated { state = .failed(error.localizedDescription) }
            }
        }
    }

    /// Resultat d'une verification : la derniere Release (nil : aucune publiee).
    func apply(latest release: ReleaseInfo?) {
        failedRelease = nil
        if let release, release.version == updatedVersion, updatedNotes == nil {
            updatedNotes = release.releaseNotes
        }
        state = release.map { $0.version > currentVersion ? .available($0) : .upToDate } ?? .upToDate
    }

    /// Apres une mise a jour, lit en silence les notes de la version installee (une fois par
    /// lancement, si la verification automatique est permise ; hors ligne, le bandeau s'en passe).
    private func fetchUpdatedNotesIfNeeded() {
        guard let version = updatedVersion, updatedNotes == nil, notesTask == nil, autoCheck else { return }
        let configuration = configuration
        notesTask = Task { [weak self] in
            var request = URLRequest(url: configuration.releaseURL(tag: version))
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue(configuration.appName, forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = ReleaseInfo.notesBody(json: data) else { return }
            guard let self, updatedVersion == version, updatedNotes == nil else { return }
            updatedNotes = ReleaseNotes(markdown: body)
        }
    }

    private nonisolated static func fetchLatest(_ configuration: UpdaterConfiguration) async throws -> ReleaseInfo? {
        var request = URLRequest(url: configuration.releaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.appName, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError("Réponse invalide du serveur.") }
        switch http.statusCode {
        case 200: break
        case 404: return nil // aucune release publiee
        case 403, 429: throw UpdateError("GitHub limite les requêtes pour le moment. Réessayez dans quelques minutes.")
        default: throw UpdateError("GitHub a répondu \(http.statusCode).")
        }
        guard let release = ReleaseInfo.parse(json: data, appName: configuration.appName) else {
            throw UpdateError("La dernière version publiée est incomplète (DMG ou empreinte manquants).")
        }
        return release
    }

    // MARK: Installation

    public func install() {
        guard let release = available, !isBusy else { return }
        let bundle = Bundle.main.bundleURL
        let parent = bundle.deletingLastPathComponent()
        guard bundle.pathExtension == "app", FileManager.default.isWritableFile(atPath: parent.path),
              FileManager.default.isWritableFile(atPath: bundle.path) else {
            NSWorkspace.shared.open(release.pageURL)
            fail(installing: release, message: "\(configuration.displayName) est installé dans un dossier protégé : la page de la version s'ouvre pour un téléchargement manuel.")
            return
        }
        let configuration = configuration
        // Occupe des maintenant : un second clic sur « Installer » (ou un check) ne lance pas une installation parallele.
        state = .downloading(0)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let staged = try await Self.prepare(release, configuration) { [weak self] progress in
                    Task { @MainActor in self?.state = .downloading(progress) }
                } onPhase: { [weak self] phase in
                    Task { @MainActor in self?.state = phase }
                }
                state = .installing
                try Self.launchReplacement(newApp: staged, destination: bundle)
                try? await Task.sleep(for: .milliseconds(400))
                NSApp.terminate(nil)
            } catch is CancellationError {
                state = .available(release)
            } catch {
                fail(installing: release, message: error.localizedDescription)
            }
        }
    }

    /// Echec : `release` est celle dont l'installation a echoue (nil pour une recherche).
    func fail(installing release: ReleaseInfo?, message: String) {
        failedRelease = release
        state = .failed(message)
    }

    /// Reprend une installation qui a echoue (bouton << Reessayer >> du bandeau).
    func retryInstall() {
        guard case .failed = state, let release = failedRelease else { return }
        failedRelease = nil
        state = .available(release)
        install()
    }

    public func dismissError() {
        if case .failed = state { state = .idle; failedRelease = nil }
    }

    /// Telecharge, verifie et extrait la nouvelle app dans un dossier temporaire.
    private nonisolated static func prepare(_ release: ReleaseInfo, _ configuration: UpdaterConfiguration,
                                            onProgress: @escaping @Sendable (Double) -> Void,
                                            onPhase: @escaping @Sendable (UpdateState) -> Void) async throws -> URL {
        let fm = FileManager.default
        let appFile = "\(configuration.appName).app"
        let work = fm.temporaryDirectory.appendingPathComponent("\(configuration.appName.lowercased())-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? fm.removeItem(at: work) } }

        // 1. Empreinte attendue.
        var req = URLRequest(url: release.checksumURL)
        req.timeoutInterval = 20
        req.setValue(configuration.appName, forHTTPHeaderField: "User-Agent")
        let (sumData, sumResponse) = try await URLSession.shared.data(for: req)
        guard (sumResponse as? HTTPURLResponse)?.statusCode == 200,
              let expected = ReleaseInfo.parseChecksum(String(decoding: sumData, as: UTF8.self), fileName: release.dmgName) else {
            throw UpdateError("L'empreinte de vérification de cette version est introuvable ou illisible.")
        }

        // 2. Telechargement.
        let dmg = work.appendingPathComponent(release.dmgName)
        try await download(release.dmgURL, to: dmg, userAgent: configuration.appName, onProgress: onProgress)
        try Task.checkCancellation()

        // 3. Verification SHA-256.
        onPhase(.verifying)
        let actual = try sha256(of: dmg)
        guard actual == expected else {
            throw UpdateError("Le fichier téléchargé est corrompu (empreinte différente). Rien n'a été installé.")
        }

        // 4. Extraction de l'app, puis controles.
        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try await run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path])
        let stage = work.appendingPathComponent("stage")
        let staged = stage.appendingPathComponent(appFile)
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            _ = try await run("/usr/bin/ditto", [mount.appendingPathComponent(appFile).path, staged.path])
        } catch {
            _ = try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            throw UpdateError("Le DMG ne contient pas \(appFile).")
        }
        _ = try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])

        guard let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == configuration.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == release.version.description else {
            throw UpdateError("L'application téléchargée ne correspond pas à la version annoncée.")
        }
        do {
            _ = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
        } catch {
            throw UpdateError("La signature de l'application téléchargée est invalide.")
        }
        succeeded = true
        return staged
    }

    private nonisolated static func download(_ url: URL, to file: URL, userAgent: String,
                                             onProgress: @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Téléchargement impossible.") }
        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var buffer = Data(); buffer.reserveCapacity(1 << 18)
        var received: Int64 = 0
        var lastReport = Date.distantPast
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 18 {
                try handle.write(contentsOf: buffer); received += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                try Task.checkCancellation()
                if total > 0, Date().timeIntervalSince(lastReport) > 0.05 {
                    onProgress(min(1, Double(received) / Double(total))); lastReport = Date()
                }
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer); received += Int64(buffer.count) }
        if total > 0, received != total { throw UpdateError("Téléchargement incomplet.") }
        onProgress(1)
    }

    private nonisolated static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Lance un script detache : il attend la fermeture de l'app, remplace le
    /// bundle (en gardant l'ancien tant que la copie n'a pas reussi), puis la rouvre.
    private nonisolated static func launchReplacement(newApp: URL, destination: URL) throws {
        let script = """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"
        i=0
        while kill -0 "$PID" 2>/dev/null; do
          i=$((i+1)); [ "$i" -gt 150 ] && exit 1
          sleep 0.1
        done
        OLD="$DEST.old-update"
        rm -rf "$OLD"
        if mv "$DEST" "$OLD"; then
          if /usr/bin/ditto "$NEW" "$DEST"; then
            rm -rf "$OLD"
          else
            rm -rf "$DEST"; mv "$OLD" "$DEST"
          fi
        fi
        rm -rf "$(dirname "$(dirname "$NEW")")"
        /usr/bin/open "$DEST"
        """
        let file = newApp.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("replace.sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [file.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do { try process.run() } catch { continuation.resume(throwing: error); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                _ = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } else {
                    continuation.resume(throwing: UpdateError("\((tool as NSString).lastPathComponent) a échoué (\(process.terminationStatus))."))
                }
            }
        }
    }
}

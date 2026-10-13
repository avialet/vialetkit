import AppKit

// Mode capture des apps (builds DEBUG) : chaque scenario rend une fenetre en PNG,
// sans autorisation d'enregistrement d'ecran (voir WindowSnapshot).

/// Une capture : un nom (le fichier) et la fenetre a rendre, preparee par l'app.
/// `window` renvoie nil quand il n'y a rien a capturer (scenario ignore avec un message).
public struct SnapshotScenario: Sendable {
    public let name: String
    public let window: @MainActor () async throws -> NSWindow?

    public init(_ name: String, window: @escaping @MainActor () async throws -> NSWindow?) {
        self.name = name
        self.window = window
    }
}

/// Demande de capture lue dans les arguments :
/// `-<prefix>Snapshot <dossier> [-<prefix>SnapshotAppearance dark] [-<prefix>SnapshotOnly a,b]
/// [-<prefix>SnapshotSize WxH]`.
public struct SnapshotRequest: Equatable, Sendable {
    public let directory: String
    public let dark: Bool
    /// Noms des scenarios a jouer ; nil : tous.
    public let only: [String]?
    /// Taille de contenu (points) des fenetres redimensionnables ; nil : inchangee.
    public let size: CGSize?

    public init(directory: String, dark: Bool, only: [String]?, size: CGSize?) {
        self.directory = directory
        self.dark = dark
        self.only = only
        self.size = size
    }

    /// nil sans `-<prefix>Snapshot <dossier>`. Une taille invalide est ignoree seule.
    public static func parse(prefix: String, arguments: [String]) -> SnapshotRequest? {
        func value(_ suffix: String) -> String? {
            guard let i = arguments.firstIndex(of: "-\(prefix)Snapshot\(suffix)"), i + 1 < arguments.count
            else { return nil }
            return arguments[i + 1]
        }
        guard let directory = value(""), !directory.isEmpty else { return nil }
        let dark = value("Appearance")?.lowercased() == "dark"
        let names = value("Only")?.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var size: CGSize?
        if let spec = value("Size") {
            let parts = spec.lowercased().split(separator: "x", omittingEmptySubsequences: false).map { Double($0) }
            if parts.count == 2, let w = parts[0], let h = parts[1], w > 0, h > 0 {
                size = CGSize(width: w, height: h)
            }
        }
        return SnapshotRequest(directory: directory, dark: dark, only: names?.isEmpty == false ? names : nil, size: size)
    }

    public func includes(_ name: String) -> Bool { only?.contains(name) ?? true }

    /// `<dossier>/<name>.png`, ou `<name>-sombre.png` en sombre.
    public func fileURL(for name: String) -> URL {
        URL(fileURLWithPath: directory).appendingPathComponent(name + (dark ? "-sombre" : "") + ".png")
    }
}

@MainActor
public enum SnapshotRunner {
    /// Lit `-<prefix>Snapshot <dossier> [-<prefix>SnapshotAppearance dark] [-<prefix>SnapshotOnly a,b]
    /// [-<prefix>SnapshotSize WxH]` dans CommandLine.arguments ; si absent, ne fait rien et renvoie false.
    /// Sinon : force l'apparence (sombre ou claire), joue chaque scenario retenu, redimensionne les
    /// fenetres redimensionnables a `size`, ecrit `<dossier>/<name>[-sombre].png`, imprime
    /// `capture : <chemin>` par fichier, puis quitte l'app. Renvoie true.
    /// A appeler depuis applicationDidFinishLaunching, apres la graine des donnees.
    @discardableResult
    public static func runIfRequested(prefix: String, scenarios: [SnapshotScenario]) -> Bool {
        guard let request = SnapshotRequest.parse(prefix: prefix, arguments: CommandLine.arguments) else {
            return false
        }
        applyAppearance(request)
        Task { @MainActor in
            await run(request, scenarios: scenarios)
            NSApp.terminate(nil)
        }
        return true
    }

    /// Scenarios joues : ceux que retient `only`, dans l'ordre ; un scenario de meme nom donne plus
    /// loin (celui de l'app) remplace le precedent (le standard) a sa place.
    public nonisolated static func plan(_ scenarios: [SnapshotScenario], for request: SnapshotRequest) -> [SnapshotScenario] {
        var ordered: [SnapshotScenario] = []
        for scenario in scenarios where request.includes(scenario.name) {
            if let i = ordered.firstIndex(where: { $0.name == scenario.name }) {
                ordered[i] = scenario
            } else {
                ordered.append(scenario)
            }
        }
        return ordered
    }

    /// `mainWindow` (apres 2 s), `settings` (fenetre de la scene Settings, ouverte par le menu), `about`
    /// (panneau A propos de l'identite) et `floatingPanel` (le FloatingPanel de l'app s'il existe :
    /// l'app l'ouvre dans sa graine, ou donne son propre scenario `floatingPanel`).
    public static func standardScenarios(mainWindow: @escaping @MainActor () -> NSWindow?,
                                         identity: AppIdentity) -> [SnapshotScenario] {
        return [
            SnapshotScenario("mainWindow") {
                try await Task.sleep(for: .seconds(2))
                return mainWindow()
            },
            SnapshotScenario("settings") {
                await newWindow { openSettings() } matching: { $0.identifier?.rawValue.contains("Settings") == true }
            },
            SnapshotScenario("about") {
                await newWindow { AboutPanel.show(identity) } matching: { _ in false }
            },
            SnapshotScenario("floatingPanel") {
                guard let panel = NSApp.windows.first(where: { $0 is FloatingPanel }) else { return nil }
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                    try await Task.sleep(for: .milliseconds(500))
                }
                return panel
            },
        ]
    }

    // MARK: - Execution

    static func run(_ request: SnapshotRequest, scenarios: [SnapshotScenario]) async {
        try? FileManager.default.createDirectory(atPath: request.directory, withIntermediateDirectories: true)
        let planned = plan(scenarios, for: request)
        for name in request.only ?? [] where !planned.contains(where: { $0.name == name }) {
            print("capture : sc\u{00E9}nario inconnu \(name)")
        }
        for scenario in planned {
            // L'app peut reposer l'apparence choisie a l'affichage de sa fenetre : on la reforce.
            applyAppearance(request)
            do {
                guard let window = try await scenario.window() else {
                    print("capture ignor\u{00E9}e : \(scenario.name) (aucune fen\u{00EA}tre)")
                    continue
                }
                if let size = request.size, window.styleMask.contains(.resizable) {
                    window.setContentSize(size)
                    window.contentView?.layoutSubtreeIfNeeded()
                    // Un tour de boucle pour que SwiftUI refasse la disposition.
                    try await Task.sleep(for: .milliseconds(500))
                }
                let url = request.fileURL(for: scenario.name)
                try WindowSnapshot.write(window, to: url)
                print("capture : \(url.path)")
            } catch {
                print("capture impossible : \(scenario.name) : \(error)")
            }
        }
    }

    /// Ouvre les Reglages : l'entree << Reglages... >> (Cmd-virgule) du menu de l'app, creee par la
    /// scene Settings ; a defaut, l'action privee `showSettingsWindow:`.
    private static func openSettings() {
        if let (menu, index) = settingsMenuItem(in: NSApp.mainMenu) {
            menu.performActionForItem(at: index)
        } else if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            print("capture : aucune commande R\u{00E9}glages")
        }
    }

    private static func settingsMenuItem(in menu: NSMenu?) -> (NSMenu, Int)? {
        guard let menu else { return nil }
        for (index, item) in menu.items.enumerated() {
            if item.keyEquivalent == ",", item.keyEquivalentModifierMask == .command { return (menu, index) }
            if let found = settingsMenuItem(in: item.submenu) { return found }
        }
        return nil
    }

    private static func applyAppearance(_ request: SnapshotRequest) {
        NSApp.appearance = NSAppearance(named: request.dark ? .darkAqua : .aqua)
    }

    /// Lance `action` puis renvoie, apres 1 s, la fenetre visible apparue entre-temps (la fenetre
    /// cle de preference), ou une fenetre visible qui satisfait `matching` ; nil sinon.
    private static func newWindow(_ action: () -> Void,
                                  matching: (NSWindow) -> Bool) async -> NSWindow? {
        let before = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        NSApp.activate()
        action()
        try? await Task.sleep(for: .seconds(1))
        let candidates = NSApp.windows.filter {
            $0.isVisible && (!before.contains(ObjectIdentifier($0)) || matching($0))
        }
        if let key = NSApp.keyWindow, candidates.contains(key) { return key }
        return candidates.first
    }
}

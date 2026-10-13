import Foundation

/// Fiche qu'une app publie pour Vialet (format 1, voir le README) :
/// `~/Library/Application Support/Vialet/apps/<bundle id>.json`, ecrit par `AppActions.publish()`.
/// Vialet decouvre ainsi les apps, leurs plaques et leurs actions sans liste en dur.
/// Les champs inconnus sont ignores ; un format plus recent reste lu pour les champs connus.
public struct HubManifest: Codable, Equatable, Sendable {
    /// Format ecrit par cette version du kit.
    public static let currentFormat = 1

    /// Teintes de l'app en `#RRGGBB` (voir `AccentPalette`).
    public struct Palette: Codable, Equatable, Sendable {
        public var accent, background, deep, pale, night, nightInk: String

        public init(_ p: AccentPalette) {
            accent = HubManifest.hex(p.accent); background = HubManifest.hex(p.background)
            deep = HubManifest.hex(p.deep); pale = HubManifest.hex(p.pale)
            night = HubManifest.hex(p.night); nightInk = HubManifest.hex(p.nightInk)
        }
    }

    public var format: Int
    public var bundleIdentifier: String
    /// Nom CamelCase ASCII (`Allege`).
    public var name: String
    public var displayName: String
    public var version: String
    /// Chemin du bundle au moment de la publication.
    public var appPath: String
    /// Schema d'URL (`allege`) : actions `<scheme>://<id>`, `<scheme>://update`.
    public var scheme: String
    /// Depot GitHub `proprietaire/nom` (Releases).
    public var repository: String
    public var site: String
    public var glyph: String
    public var strokeDeep: Bool
    public var palette: Palette
    public var actions: [AppAction]

    public init(identity: AppIdentity, version: String, appPath: String, scheme: String, actions: [AppAction]) {
        format = Self.currentFormat
        bundleIdentifier = identity.bundleIdentifier
        name = identity.name
        displayName = identity.displayName
        self.version = version
        self.appPath = appPath
        self.scheme = scheme
        repository = identity.repository
        site = identity.siteURL.absoluteString
        glyph = identity.glyph
        strokeDeep = identity.strokeDeep
        palette = Palette(identity.palette)
        self.actions = actions
    }

    /// La palette, si toutes ses teintes sont lisibles.
    public var accentPalette: AccentPalette? {
        let p = palette
        guard let a = Self.parseHex(p.accent), let b = Self.parseHex(p.background), let d = Self.parseHex(p.deep),
              let pa = Self.parseHex(p.pale), let n = Self.parseHex(p.night), let ni = Self.parseHex(p.nightInk)
        else { return nil }
        return AccentPalette(accent: a, background: b, deep: d, pale: pa, night: n, nightInk: ni)
    }

    // MARK: JSON

    /// JSON lisible : indente, cles triees, barres non echappees.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// nil si le JSON est illisible, sans format (>= 1) ou s'il manque un champ. Les actions dont
    /// l'identifiant est invalide ou reserve sont retirees.
    public static func decode(_ data: Data) -> HubManifest? {
        guard var m = try? JSONDecoder().decode(HubManifest.self, from: data), m.format >= 1,
              !m.bundleIdentifier.isEmpty else { return nil }
        m.actions = m.actions.filter { AppAction.isValidIdentifier($0.id) && !AppURLCommand.reserved.contains($0.id) }
        return m
    }

    public static func hex(_ value: UInt32) -> String { String(format: "#%06X", value & 0xFFFFFF) }

    /// `#RRGGBB` -> valeur ; nil sinon.
    public static func parseHex(_ text: String) -> UInt32? {
        guard text.count == 7, text.first == "#" else { return nil }
        let digits = text.dropFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(digits, radix: 16)
    }

    // MARK: Fichiers

    /// `~/Library/Application Support/Vialet/apps`
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vialet/apps", isDirectory: true)
    }

    public static func fileURL(bundleIdentifier: String, in directory: URL) -> URL {
        directory.appendingPathComponent(bundleIdentifier + ".json")
    }

    /// Ecrit `<dossier>/<bundle id>.json` (dossier cree au besoin, ecriture atomique).
    public func write(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoded().write(to: Self.fileURL(bundleIdentifier: bundleIdentifier, in: directory), options: .atomic)
    }

    /// Toutes les fiches lisibles d'un dossier (`*.json`), triees par bundle id.
    public static func loadAll(from directory: URL) -> [HubManifest] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(decode) }
            .sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    /// Publier seulement depuis un dossier Applications (`/Applications`, `~/Applications`, ou un
    /// sous-dossier) : pas depuis `build/`, une image disque ou une translocation.
    public static func shouldPublish(bundleURL: URL, home: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let roots = ["/Applications/", home.standardizedFileURL.path + "/Applications/"]
        return roots.contains { path.hasPrefix($0) }
    }

    /// Notification distribuee par une app apres avoir publie sa fiche : Vialet la relit.
    public static let appsChangedNotification = Notification.Name("fr.vialet.apps.changed")

    public static func postAppsChanged() {
        DistributedNotificationCenter.default().postNotificationName(appsChangedNotification, object: nil,
                                                                    userInfo: nil, deliverImmediately: true)
    }
}

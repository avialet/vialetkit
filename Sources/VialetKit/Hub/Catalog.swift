import Foundation

/// Une app du catalogue du hub (https://vialet.app/apps.json).
public struct CatalogEntry: Equatable, Sendable {
    /// Nom affiche (accents permis).
    public let name: String
    /// Nom CamelCase ASCII (`Allege`) : bundle `fr.vialet.<brand minuscule>`.
    public let brand: String
    /// Site de l'app (https seulement) ; nil si absent ou invalide.
    public let url: URL?
    public let tagline: String
    /// `available` (defaut) ou autre (`soon`...).
    public let status: String

    public init(name: String, brand: String, url: URL?, tagline: String, status: String) {
        self.name = name; self.brand = brand; self.url = url; self.tagline = tagline; self.status = status
    }

    public var isAvailable: Bool { status == "available" }
    public var bundleIdentifier: String { "fr.vialet." + brand.lowercased() }
}

/// Catalogue du hub : ordre des apps dans le menu, apps a decouvrir. Lu au plus une fois par jour.
public enum Catalog {
    public static let url = URL(string: "https://vialet.app/apps.json")!
    /// Intervalle minimal entre deux lectures (24 h).
    public static let refreshInterval: TimeInterval = 24 * 3600
    /// Taille maximale du catalogue (reponse ou cache) : 1 Mo.
    public static let maxSize = 1024 * 1024

    /// `{"apps": [{name, brand, url, tagline, status}]}` ; nil si ce n'est pas cette forme ou si les
    /// donnees depassent `maxSize`. Une entree sans `brand` est ignoree ; un lien non https devient nil.
    public static func parse(_ data: Data) -> [CatalogEntry]? {
        guard data.count <= maxSize, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["apps"] as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let brand = item["brand"] as? String, !brand.isEmpty else { return nil }
            let link = (item["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            return CatalogEntry(name: item["name"] as? String ?? brand, brand: brand, url: link,
                                tagline: item["tagline"] as? String ?? "",
                                status: item["status"] as? String ?? "available")
        }
    }

    /// Catalogue en cache : fichier ordinaire (pas un FIFO qui bloquerait la lecture), taille verifiee avant.
    public static func load(from url: URL) -> [CatalogEntry]? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= maxSize,
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    /// Lecture due : jamais lu, plus de 24 h, ou horloge reculee.
    public static func shouldRefresh(now: Date, lastFetch: Date?) -> Bool {
        guard let lastFetch else { return true }
        let elapsed = now.timeIntervalSince(lastFetch)
        return elapsed < 0 || elapsed >= refreshInterval
    }
}

import Foundation

/// Une version publiee, extraite de la reponse de l'API GitHub `releases/latest`.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let notes: String
    public let pageURL: URL
    public let dmgURL: URL
    public let dmgName: String
    public let checksumURL: URL

    /// Hotes autorises pour les telechargements (GitHub et son CDN de fichiers).
    static let allowedHosts: Set<String> = ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]

    private struct Payload: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let body: String?
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// Analyse la reponse JSON. Renvoie nil si la release est un brouillon, une
    /// pre-version, si le tag n'est pas une version, ou s'il manque le DMG
    /// `<appName>-X.Y.Z.dmg` (dont la version doit egaler le tag) ou son `.sha256`.
    public static func parse(json: Data, appName: String) -> ReleaseInfo? {
        guard let p = try? JSONDecoder().decode(Payload.self, from: json),
              p.draft != true, p.prerelease != true,
              let version = SemanticVersion(string: p.tag_name),
              let page = secureURL(p.html_url) else { return nil }
        let dmgName = "\(appName)-\(version).dmg"
        guard let dmg = p.assets.first(where: { $0.name == dmgName }),
              let sum = p.assets.first(where: { $0.name == dmgName + ".sha256" }),
              let dmgURL = secureURL(dmg.browser_download_url),
              let sumURL = secureURL(sum.browser_download_url) else { return nil }
        return ReleaseInfo(version: version, notes: p.body ?? "", pageURL: page, dmgURL: dmgURL,
                           dmgName: dmgName, checksumURL: sumURL)
    }

    private static func secureURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host) else { return nil }
        return url
    }

    /// Extrait l'empreinte SHA-256 (64 caracteres hexadecimaux) d'un fichier `.sha256`
    /// au format `shasum` : `<hash>  <nom>`. Si un nom est donne, la ligne doit le citer.
    public static func parseChecksum(_ text: String, fileName: String? = nil) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let hash = fields.first, hash.count == 64,
                  hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { continue }
            if let fileName, let name = fields.dropFirst().last,
               name.trimmingCharacters(in: CharacterSet(charactersIn: "*")) != fileName { continue }
            return hash.lowercased()
        }
        return nil
    }
}
